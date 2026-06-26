-- | Structured JSON logging with auto-injected timestamp and level.
--
-- @
-- -- Primary API: Logger record (path bound once)
-- logger <- newLogger "logs/app.log"
-- logger.logInfo "Server started" []
-- logger.logError "SMTP failed" [("error", Aeson.String "refused")]
--
-- -- Convenience: standalone functions (path passed per call)
-- logInfoWith "logs/app.log" "Server started" []
-- @
module Lurk.Log
    ( Log
    , LogWith
    , LogLevel (..)
    , Logger(..)
    , newLogger
    , logDebugWith
    , logInfoWith
    , logWarningWith
    , logErrorWith
    , levelToText
    ) where

import Control.Concurrent.MVar (MVar, newMVar, modifyMVar)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Lurk.Env (getEnvWithDefault)
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (takeDirectory)
import System.IO.Unsafe (unsafePerformIO)

-- | A logging action: message + structured fields.
type Log = Text -> [(Text, Aeson.Value)] -> IO ()

-- | A standalone logging action: file path + message + structured fields.
type LogWith = FilePath -> Text -> [(Text, Aeson.Value)] -> IO ()

-- | Log level for filtering output.
data LogLevel = LevelDebug | LevelInfo | LevelWarning | LevelError
    deriving (Show, Eq, Ord)

levelToText :: LogLevel -> Text
levelToText LevelDebug   = "debug"
levelToText LevelInfo    = "info"
levelToText LevelWarning = "warning"
levelToText LevelError   = "error"

parseLevel :: Text -> LogLevel
parseLevel t = case T.toLower t of
    "debug"   -> LevelDebug
    "info"    -> LevelInfo
    "warning" -> LevelWarning
    "error"   -> LevelError
    _         -> LevelInfo

-- | Global map of per-file mutexes.
{-# NOINLINE lockMap #-}
lockMap :: TVar (Map.Map FilePath (MVar ()))
lockMap = unsafePerformIO $ newTVarIO Map.empty

-- | Get or create a mutex for the given file path.
getLock :: FilePath -> IO (MVar ())
getLock path = do
    mv <- newMVar ()
    atomically $ do
        m <- readTVar lockMap
        case Map.lookup path m of
            Just v  -> pure v
            Nothing -> do
                writeTVar lockMap (Map.insert path mv m)
                pure mv

-- | Run an action while holding the mutex for the given file path.
withFileLock :: FilePath -> IO a -> IO a
withFileLock path action = do
    mv <- getLock path
    modifyMVar mv $ \() -> do
        result <- action
        pure ((), result)

-- | Write a JSONL entry to the file, appending to existing content.
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

----------------------------------------------------------------------
-- LOGGER RECORD
----------------------------------------------------------------------

-- | Logger with level-specific functions. Each function is bound to a file path.
data Logger = Logger
  { logDebug   :: Log
  , logInfo    :: Log
  , logWarning :: Log
  , logError   :: Log
  }

-- | Create a logger bound to the given file path.
--   Reads @LURK_LOG_LEVEL@ from the environment (default: @"info"@).
--   The log directory is created automatically.
newLogger :: FilePath -> IO Logger
newLogger path = do
    raw <- getEnvWithDefault "LURK_LOG_LEVEL" "info"
    let minLevel = parseLevel raw
    createDirectoryIfMissing True (takeDirectory path)
    pure Logger
      { logDebug   = if minLevel <= LevelDebug   then writeLog path LevelDebug   else \_ _ -> pure ()
      , logInfo    = if minLevel <= LevelInfo    then writeLog path LevelInfo    else \_ _ -> pure ()
      , logWarning = if minLevel <= LevelWarning then writeLog path LevelWarning else \_ _ -> pure ()
      , logError   = writeLog path LevelError
      }

----------------------------------------------------------------------
-- STANDALONE FUNCTIONS (LogWith)
----------------------------------------------------------------------

-- | Log at debug level to the given file path.
logDebugWith :: LogWith
logDebugWith path msg fields = writeLog path LevelDebug msg fields

-- | Log at info level to the given file path.
logInfoWith :: LogWith
logInfoWith path msg fields = writeLog path LevelInfo msg fields

-- | Log at warning level to the given file path.
logWarningWith :: LogWith
logWarningWith path msg fields = writeLog path LevelWarning msg fields

-- | Log at error level to the given file path.
logErrorWith :: LogWith
logErrorWith path msg fields = writeLog path LevelError msg fields
