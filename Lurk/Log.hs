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
    , Logger(..)
    , newLogger
    , logDebugWith
    , logInfoWith
    , logWarningWith
    , logErrorWith
    ) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (formatTime, defaultTimeLocale)
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (takeDirectory)

-- | A logging action: message + structured fields.
type Log = Text -> [(Text, Aeson.Value)] -> IO ()

-- | A standalone logging action: file path + message + structured fields.
type LogWith = FilePath -> Text -> [(Text, Aeson.Value)] -> IO ()

----------------------------------------------------------------------
-- INTERNALS
----------------------------------------------------------------------

data LogLevel = LevelDebug | LevelInfo | LevelWarning | LevelError
    deriving (Show, Eq, Ord)

levelToText :: LogLevel -> Text
levelToText LevelDebug   = "debug"
levelToText LevelInfo    = "info"
levelToText LevelWarning = "warning"
levelToText LevelError   = "error"

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
--   The log directory is created automatically.
newLogger :: FilePath -> IO Logger
newLogger path = do
    createDirectoryIfMissing True (takeDirectory path)
    pure Logger
      { logDebug   = writeLog path LevelDebug
      , logInfo    = writeLog path LevelInfo
      , logWarning = writeLog path LevelWarning
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
