# Session Rolling Expiration + ISO 8601

## Goal

Replace single `sessionExpiry` with two independent expiration fields and fix UTCTime serialization.

## Modes (based on `Config` fields)

| `sessionMaxAge` | `sessionIdle` | Behavior |
|-----------------|---------------|----------|
| `Just 604800` | `Nothing` | Strict: 7 days from creation, never refreshes |
| `Nothing` | `Just 604800` | Rolling: 7 days from last activity |
| `Just 2592000` | `Just 604800` | Rolling + cap: refreshes on activity, max 30 days |
| `Nothing` | `Nothing` | Default: strict 24h |

## Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `lib/lurk/Lurk/Session.hs` | Core: new `Session` fields, ISO 8601, dual expiry, store fields |
| 2 | `lib/lurk/Lurk/Session/Middleware.hs` | Rolling refresh on access, new session creation |
| 3 | `lib/lurk/Lurk/App.hs` | `runLurk :: Config -> LurkApp -> IO ()` |
| 4 | `lib/lurk/Lurk/Prelude.hs` | Update re-export |
| 5 | `lib/lurk/test/SessionSpec.hs` | Update all tests for new `Session` type |
| 6 | `Main.hs` | `runLurk cfg router` |

---

## 1. `Lurk/Session.hs`

**New imports:**
```haskell
import Data.Time.Format (formatTime, parseTimeM, defaultTimeLocale)
import Data.Maybe (mapMaybe, isJust)
```

**`Session` record:**
```haskell
data Session = Session
    { sessionId          :: SessionId
    , sessionData        :: Map Text Text
    , sessionAbsoluteExp :: Maybe UTCTime  -- Immutable. Set at creation.
    , sessionIdleExp     :: Maybe UTCTime  -- Refreshes on access.
    }
```

**`SessionStore` record:**
```haskell
data SessionStore
    = InMemoryStore
        { storeSessions    :: TVar (Map SessionId Session)
        , storeMaxAge      :: Maybe Int
        , storeIdleTimeout :: Maybe Int
        }
    | FileStore
        { storeSessions    :: TVar (Map SessionId Session)
        , storeMaxAge      :: Maybe Int
        , storeIdleTimeout :: Maybe Int
        , storeDir         :: FilePath
        }
```

**Delete `readSessionMaxAge`.** Config flows from `Config` -> `runLurk` -> store constructors.

**New helpers:**
```haskell
isSessionExpired :: UTCTime -> Session -> Bool
isSessionExpired now Session{..} =
    maybe False (<= now) sessionAbsoluteExp
    || maybe False (<= now) sessionIdleExp

refreshIdleExp :: Maybe Int -> UTCTime -> Session -> Session
refreshIdleExp Nothing _ sess = sess
refreshIdleExp (Just timeout) now sess =
    sess { sessionIdleExp = Just (addUTCTime (fromIntegral timeout) now) }

newSessionExps :: Maybe Int -> Maybe Int -> UTCTime -> (Maybe UTCTime, Maybe UTCTime)
newSessionExps mMaxAge mIdle now =
    let absExp = case mMaxAge of
            Just age -> Just (addUTCTime (fromIntegral age) now)
            Nothing  -> case mIdle of
                Just idle -> Just (addUTCTime (fromIntegral idle) now)
                Nothing   -> Just (addUTCTime 86400 now)
        idleExp = (`addUTCTime` now) . fromIntegral <$> mIdle
    in (absExp, idleExp)
```

**Update constructors** -- `newSessionStore` and `newFileSessionStore` take `Maybe Int -> Maybe Int -> ...`:
```haskell
newSessionStore :: Maybe Int -> Maybe Int -> IO SessionStore
newSessionStore mMaxAge mIdle =
    InMemoryStore <$> newTVarIO Map.empty <*> pure mMaxAge <*> pure mIdle

newFileSessionStore :: Maybe Int -> Maybe Int -> FilePath -> IO SessionStore
newFileSessionStore mMaxAge mIdle dir = do
    createDirectoryIfMissing True dir
    sessions <- loadAllSessions dir
    FileStore <$> newTVarIO sessions <*> pure mMaxAge <*> pure mIdle <*> pure dir
```

**Update `newSession`** -- use `newSessionExps`:
```haskell
newSession store = do
    now <- liftIO getCurrentTime
    sid <- liftIO newSessionId
    let (absExp, idleExp) = newSessionExps (storeMaxAge store) (storeIdleTimeout store) now
    let sess = Session { sessionId = sid, sessionData = Map.empty
                       , sessionAbsoluteExp = absExp, sessionIdleExp = idleExp }
    liftIO $ atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
    pure sess
```

**Update `getSession`** -- check `isSessionExpired`, refresh idle:
```haskell
getSession store = do
    req <- request
    case TE.decodeUtf8 <$> lookup (CI.mk "X-Lurk-Session-Id") (requestHeaders req) of
        Just sid -> do
            sessions <- liftIO $ readTVarIO (storeSessions store)
            case Map.lookup sid sessions of
                Just sess -> do
                    now <- liftIO getCurrentTime
                    if isSessionExpired now sess
                        then newSession store
                        else do
                            let refreshed = refreshIdleExp (storeIdleTimeout store) now sess
                            liftIO $ atomically $ modifyTVar' (storeSessions store) (Map.insert sid refreshed)
                            pure refreshed
                Nothing -> newSession store
        Nothing -> newSession store
```

**Update `loadAllSessions`** -- use `isSessionExpired`:
```haskell
loadOneSession now dir acc fileName = do
    -- ...
    case parseSessionFile (T.pack fileName) content of
        Just sess
            | not (isSessionExpired now sess) -> pure (Map.insert (sessionId sess) sess acc)
            | otherwise -> removeFile path >> pure acc
        Nothing -> pure acc
```

**Update `parseSessionFile`** -- ISO 8601, two expiry lines:
```
-- File format:
--   line 1: absolute expiry (ISO 8601 or empty)
--   line 2: idle expiry (ISO 8601 or empty)
--   line 3+: key=value pairs
```

```haskell
parseSessionFile :: SessionId -> BS.ByteString -> Maybe Session
parseSessionFile sid content =
    case BC.lines content of
        (absLine:idleLine:kvLines) -> do
            let absExp  = parseISO8601 (T.unpack $ BC.strip absLine)
                idleExp = parseISO8601 (T.unpack $ BC.strip idleLine)
                kvs     = mapMaybe parseKV kvLines
            if isJust absExp || isJust idleExp
                then Just Session { sessionId = sid, sessionData = Map.fromList kvs
                                  , sessionAbsoluteExp = absExp, sessionIdleExp = idleExp }
                else Nothing
        _ -> Nothing

parseISO8601 :: String -> Maybe UTCTime
parseISO8601 "" = Nothing
parseISO8601 s  = parseTimeM False defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" s
```

**Update `persistSession`** -- ISO 8601, two expiry lines:
```haskell
persistSession FileStore{..} Session{..}
    | not (T.all (`elem` ("0123456789abcdef" :: String)) sessionId) = pure ()
    | otherwise = do
        let path     = storeDir </> T.unpack sessionId
        let tmpPath  = path ++ ".tmp"
        let fmt      = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"
        let absLine  = maybe "" fmt sessionAbsoluteExp
        let idleLine = maybe "" fmt sessionIdleExp
        let kvLines  = map (\(k, v) -> TE.encodeUtf8 k <> "=" <> TE.encodeUtf8 v) $ Map.toList sessionData
        let content  = BC.pack absLine <> "\n" <> BC.pack idleLine <> "\n"
                    <> BC.intercalate "\n" kvLines <> "\n"
        BS.writeFile tmpPath content
        renameFile tmpPath path
```

**Update `cleanupSessions`** -- use `isSessionExpired`:
```haskell
cleanupSessions store = forkIO $ forever $ do
    threadDelay (5 * 60 * 1000000)
    now <- getCurrentTime
    expired <- atomically $ do
        sessions <- readTVar (storeSessions store)
        let expired = Map.filter (isSessionExpired now) sessions
        writeTVar (storeSessions store) (Map.filter (not . isSessionExpired now) sessions)
        pure expired
    case store of
        FileStore{..} -> mapM_ (\sid -> removeFile (storeDir </> T.unpack sid)) (Map.keys expired)
        _ -> pure ()
```

**Update module exports:** remove `readSessionMaxAge`.

---

## 2. `Lurk/Session/Middleware.hs`

**Update imports:** remove `System.Environment (lookupEnv)`.

**Update `sessionMiddleware`** -- use `isSessionExpired`:
```haskell
sessionMiddleware store app req respond = do
    let mCookieSid = parseSessionCookie req
    case mCookieSid of
        Just sid -> do
            sessions <- readTVarIO (storeSessions store)
            case Map.lookup sid sessions of
                Just sess -> do
                    now <- getCurrentTime
                    if isSessionExpired now sess
                        then do
                            atomically $ modifyTVar' (storeSessions store) (Map.delete sid)
                            removeSessionFile store sid
                            newSessionAndContinue store app req respond
                        else continueWithSession sid app req respond
                Nothing -> newSessionAndContinue store app req respond
        Nothing -> newSessionAndContinue store app req respond
```

**Update `newSessionAndContinue`** -- use `newSessionExps`:
```haskell
newSessionAndContinue store app req respond = do
    now <- getCurrentTime
    sid <- newSessionId
    let (absExp, idleExp) = newSessionExps (storeMaxAge store) (storeIdleTimeout store) now
    let sess = Session { sessionId = sid, sessionData = Map.empty
                       , sessionAbsoluteExp = absExp, sessionIdleExp = idleExp }
    atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
    -- ... cookie unchanged ...
```

---

## 3. `Lurk/App.hs`

**Change `runLurk` signature:**
```haskell
runLurk :: Config -> LurkApp -> IO ()
runLurk cfg app = do
    env <- Lurk.Env.loadEnv
    atomically $ writeTVar envRef (Just env)
    store <- newFileSessionStore (sessionMaxAge cfg) (sessionIdle cfg) ".lurk-sessions"
    atomically $ writeTVar storeRef (Just store)
    _ <- cleanupSessions store
    scotty (port cfg) $ do
        middleware (sessionMiddleware store)
        middleware (csrfMiddleware store)
        app
```

**Update export list:** `runLurk` already exported.

---

## 4. `Lurk/Prelude.hs`

Remove `readSessionMaxAge` from re-exports. Everything else stays (`Session(..)` already exports all fields).

---

## 5. `test/SessionSpec.hs`

- All `Session` constructors: replace `sessionExpiry = ...` with `sessionAbsoluteExp = ...`, `sessionIdleExp = ...`
- `newSessionStore` calls: add two `Nothing` args
- `newFileSessionStore` calls: add two `Nothing` args
- `testPersistSession`: assert two expiry lines in file
- `testFileStore`: format expectations updated
- New tests: `testRollingExpiration`, `testStrictExpiration`, `testISO8601Roundtrip`

---

## 6. `Main.hs`

```haskell
main :: IO ()
main = do
    cfg <- loadConfig
    putStrLn $ "Starting on http://localhost:" ++ show (port cfg)
    runLurk cfg router
```
