# Lurk.Log Improvements

## Goal

Fix race condition in concurrent logging and add minimum log level filtering via `Config`.

## Log Append
**Locking:** LOW — standalone
**Easiness:** EASY — change one function

**Problem:** `writeLog` creates `.tmp` file, writes one entry, renames to target. Overwrites entire log file each time — only last entry survives.

**Fix:** Read existing content, append new entry, write back. Or use `appendFile` / `openFile AppendMode`.

**Files:** `Lurk/Log.hs` (lines 52-64)

---

### 6. SMTP Certificate Validation
**Locking:** LOW — standalone
**Easiness:** EASY — change one boolean

**Problem:** `settingDisableCertificateValidation = True` — disables TLS certificate verification by default. Insecure.

**Fix:** Add `smtpDisableCertValidation :: Bool` field to `SmtpConfig` (default `False`). Only disable when explicitly configured.

**Files:** `Lurk/Email/SMTP.hs` (line 64)

---

## 1. Per-path mutex (race condition fix)

**Problem:** Two concurrent `writeLog` calls to the same file read the same existing content, then both write — one entry lost.

**Solution:** Per-file-path `MVar` mutex using a global `TVar (Map FilePath (MVar ()))`. Blocks concurrent threads writing to the same file. Safe on all platforms, no `flock` complexity.

**Note:** `flock` was attempted but conflicts with GHC's `withFile` + `renameFile` on Linux ("Bad file descriptor"). MVar is simpler and correct. A future task will replace `unsafePerformIO` for the global state (`lockMap`, `storeRef`, `envRef`).

### Files to modify

| # | File | Change |
|---|------|--------|
| 1 | `Lurk/Log.hs` | Add `lockMap`, `getLock`, `withFileLock`, wrap `writeLog` body |
| 2 | `test/LogSpec.hs` | Add concurrent write test using `forkIO` + `MVar` (base-only) |

### `Lurk/Log.hs` changes

**New imports:**
```haskell
import Control.Concurrent.MVar (MVar, newEmptyMVar, modifyMVar)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Data.Map.Strict qualified as Map
import System.IO.Unsafe (unsafePerformIO)
```

**Global lock map:**
```haskell
-- | Global map of per-file mutexes.
{-# NOINLINE lockMap #-}
lockMap :: TVar (Map.Map FilePath (MVar ()))
lockMap = unsafePerformIO $ newTVarIO Map.empty
```

**Lock acquisition:**
```haskell
getLock :: FilePath -> IO (MVar ())
getLock path = do
    mv <- newEmptyMVar
    atomically $ do
        m <- readTVar lockMap
        case Map.lookup path m of
            Just v  -> pure v
            Nothing -> do
                writeTVar lockMap (Map.insert path mv m)
                pure mv
```

Race-safe: `atomically` ensures only one thread sees `Nothing` and inserts. Others get the existing `MVar`.

**Lock wrapper:**
```haskell
withFileLock :: FilePath -> IO a -> IO a
withFileLock path action = do
    mv <- getLock path
    modifyMVar mv $ \() -> do
        result <- action
        pure ((), result)
```

`modifyMVar` releases the `MVar` on exception automatically.

**Updated `writeLog`:**
```haskell
writeLog :: FilePath -> LogLevel -> Text -> [(Text, Aeson.Value)] -> IO ()
writeLog path level msg fields = do
    now <- getCurrentTime
    let timestamp = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now
    let entry = Aeson.object $
            [ "level"     Aeson..= levelToText level
            , "message"   Aeson..= msg
            , "timestamp" Aeson..= timestamp
            ]
            ++ map (\(k, v) -> Key.fromText k Aeson..= v) fields
    let tmpPath = path ++ ".tmp"
    withFileLock path $ do
        createDirectoryIfMissing True (takeDirectory path)
        exists <- doesFileExist path
        existing <- if exists then LBS.readFile path else pure ""
        LBS.writeFile tmpPath (existing <> Aeson.encode entry <> "\n")
        renameFile tmpPath path
```

**Key detail:** `createDirectoryIfMissing` moves inside the lock to avoid TOCTOU between directory creation and file open.

### `test/LogSpec.hs` changes

New test case in `testWriteLog` (using `forkIO` + `MVar` from `base`):
```haskell
, testCase "concurrent writes preserve all entries" $ do
    withSystemTempDirectory "log-test" $ \tmpDir -> do
        let path = tmpDir </> "race.log"
        let n = 50
        done <- newEmptyMVar
        mapM_ (\i ->
            forkIO $ do
                logInfoWith path (T.pack $ "entry-" ++ show i) []
                putMVar done ()) [1..n]
        replicateM_ n (takeMVar done)
        content <- LBS.readFile path
        assertEqual "all entries present" n (length (linesOf content))
```

New imports: `Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)`, `Control.Monad (replicateM_)`.

No new dependencies — `base` only.

---

## 2. Minimum log level filtering

**Problem:** No way to suppress debug/info in production. All levels always write.

**Solution:** Add `minLogLevel :: LogLevel` to `Config`. Thread it through to `Logger`. Skip write when level < minLevel.

### Files to modify

| # | File | Change |
|---|------|--------|
| 1 | `Lurk/Log.hs` | Export `LogLevel(..)`, add `minLogLevel` to `Logger`, update `newLogger` |
| 2 | `Lurk/App.hs` | Add `minLogLevel` field to `Config`, pass to logger creation |
| 3 | `Lurk/Prelude.hs` | Re-export `LogLevel(..)` |
| 4 | `Main.hs` | Add `minLogLevel = LevelInfo` to `loadConfig` |
| 5 | `lib/lurk/templates/website/Main.hs` | Same |
| 6 | `test/LogSpec.hs` | Add level filtering tests |

### `Lurk/Log.hs` changes

**Export list:** Add `LogLevel(..)`.

**`Logger` record:**
```haskell
data Logger = Logger
  { logDebug   :: Log
  , logInfo    :: Log
  , logWarning :: Log
  , logError   :: Log
  , minLogLevel :: LogLevel  -- NEW
  }
```

**`newLogger`:**
```haskell
newLogger :: LogLevel -> FilePath -> IO Logger
newLogger minLevel path = do
    createDirectoryIfMissing True (takeDirectory path)
    pure Logger
      { logDebug   = if LevelDebug >= minLevel then writeLog path LevelDebug else \_ _ -> pure ()
      , logInfo    = if LevelInfo >= minLevel then writeLog path LevelInfo else \_ _ -> pure ()
      , logWarning = if LevelWarning >= minLevel then writeLog path LevelWarning else \_ _ -> pure ()
      , logError   = writeLog path LevelError  -- always log errors
      , minLogLevel = minLevel
      }
```

**Design decisions:**
- `logError` always writes regardless of `minLevel` — errors should never be silently dropped.
- Filtering happens at `Logger` construction time, not per-call — zero runtime overhead for filtered levels.
- `LogLevel` derives `Ord` (already does: `LevelDebug < LevelInfo < LevelWarning < LevelError`).

**Standalone functions** (`logInfoWith`, etc.) — remain unchanged. They don't use `Logger`, so filtering doesn't apply. Users who want filtering should use the `Logger` API.

### `Lurk/App.hs` changes

**`Config`:**
```haskell
data Config = Config
    { port          :: Int
    , domain        :: Text
    , sessionMaxAge :: Maybe Int
    , sessionIdle   :: Maybe Int
    , minLogLevel   :: LogLevel  -- NEW, default: LevelInfo
    }
```

**Import:** Add `import Lurk.Log (LogLevel(..))`.

**Note:** `Config` currently doesn't import from `Lurk.Log`. This creates a dependency from `Lurk.App` -> `Lurk.Log`. Check for circular imports — `Lurk.Log` does not import `Lurk.App`, so this is safe.

### `Lurk/Prelude.hs` changes

Add `LogLevel(..)` to the re-export list from `Lurk.Log`.

### `Main.hs` (website) changes

```haskell
loadConfig :: IO Config
loadConfig = do
    pure Config
        { port          = 3003
        , domain        = P.domain
        , sessionMaxAge = Nothing
        , sessionIdle   = 259200
        , minLogLevel   = LevelInfo
        }
```

### `Controller/Form.hs` changes

```haskell
-- Before:
smtpLogger <- liftIO $ newLogger "logs/smtp.log"

-- After:
cfg <- liftIO getConfig  -- need access to Config, or pass minLogLevel explicitly
smtpLogger <- liftIO $ newLogger (minLogLevel cfg) "logs/smtp.log"
```

**Alternative (simpler):** Since `Controller/Form.hs` currently hardcodes log paths, and the min level should be app-wide, add a global `Logger` created at startup in `runLurk` and stored in a `TVar` (similar to `storeRef`/`envRef`). Or pass `Config` through to handlers.

**Recommended approach:** Store `minLogLevel` in a global `TVar` (like `envRef`) and have `newLogger` read it:
```haskell
-- In Lurk/App.hs:
{-# NOINLINE logLevelRef #-}
logLevelRef :: TVar (Maybe LogLevel)
logLevelRef = unsafePerformIO $ newTVarIO Nothing

-- In runLurk:
atomically $ writeTVar logLevelRef (Just (minLogLevel cfg))

-- In Lurk/Log.hs:
newLogger :: FilePath -> IO Logger
newLogger path = do
    mLevel <- readTVarIO logLevelRef
    let minLevel = fromMaybe LevelInfo mLevel
    -- ... rest unchanged
```

This avoids changing `newLogger`'s signature (breaking change) and keeps the API clean. The `Config` field controls the global default.

### `test/LogSpec.hs` changes

New test group:
```haskell
testLevelFiltering :: TestTree
testLevelFiltering = testGroup "level filtering"
    [ testCase "debug suppressed when minLevel is Info" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "filtered.log"
            logger <- newLogger LevelInfo path  -- need new signature
            logDebug logger "should not appear" []
            exists <- doesFileExist path
            -- File may not exist (no writes) or be empty
            if exists
                then do
                    content <- LBS.readFile path
                    assertBool "no debug entry" (T.null (TE.decodeUtf8 (LBS.toStrict content)))
                else assertBool "no file created" True
    , testCase "info logged when minLevel is Info" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "filtered.log"
            logger <- newLogger LevelInfo path
            logInfo logger "should appear" []
            content <- LBS.readFile path
            assertBool "has info" (contentHas content "should appear")
    , testCase "errors always logged regardless of minLevel" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "filtered.log"
            logger <- newLogger LevelError path
            logError logger "always logged" []
            content <- LBS.readFile path
            assertBool "has error" (contentHas content "always logged")
    ]
```

---

## Implementation order

1. `Lurk/Log.hs` — Add `lockMap`, `getLock`, `withFileLock`, update `writeLog`, export `LogLevel(..)`, add `minLogLevel` to `Logger`, update `newLogger`
2. `Lurk/App.hs` — Add `minLogLevel` to `Config`, add `logLevelRef`, update `runLurk`
3. `Lurk/Prelude.hs` — Re-export `LogLevel(..)`
4. `Main.hs` + `templates/website/Main.hs` — Add `minLogLevel = LevelInfo`
5. `Controller/Form.hs` — Use global `newLogger` (no signature change needed if using `logLevelRef`)
6. `test/LogSpec.hs` — Add concurrent test + level filtering tests

## Future: Replace `unsafePerformIO`

The global state uses `unsafePerformIO` for `lockMap` (Log), `storeRef`/`envRef` (App). Plan to replace with `ReaderT AppCtx` or similar, threading state through `runLurk`. Low priority — works fine for single-server deployments.

---

## Risk assessment

| Change | Risk | Mitigation |
|--------|------|------------|
| MVar mutex | LOW — standard concurrency primitive, exception-safe via `modifyMVar` | Per-path granularity limits contention |
| `LogLevel` in Config | LOW — new field, existing code gets default via `logLevelRef` | `fromMaybe LevelInfo` fallback |
| `newLogger` signature | NONE — kept unchanged, filtering via global `logLevelRef` | No breaking API change |
| Concurrent test | LOW — base-only deps, deterministic barrier via `MVar` | `forkIO` + `takeMVar` barrier |
