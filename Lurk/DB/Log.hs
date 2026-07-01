-- | Query logging with execution time tracking.
-- Integrates with Lurk's structured JSON logging.
module Lurk.DB.Log
    ( QueryLog(..)
    , QueryLogger
    , defaultQueryLogger
    , silentLogger
    ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Data.Aeson qualified as Aeson
import Lurk.Log (Logger(..))

-- | A single query log entry.
data QueryLog = QueryLog
  { querySQL      :: Text       -- ^ SQL template with ? placeholders
  , queryBindings :: [Text]     -- ^ Bound parameter values
  , queryTimeMs   :: Double     -- ^ Execution time in milliseconds
  } deriving (Show)

-- | A function that receives query log entries.
type QueryLogger = QueryLog -> IO ()

-- | Default logger that writes to Lurk's structured log at debug level.
defaultQueryLogger :: Logger -> QueryLogger
defaultQueryLogger logger qlog = do
    let sql = querySQL qlog
        bindings = queryBindings qlog
        timeMs = queryTimeMs qlog
    logDebug logger "DB query"
        [ ("sql", Aeson.String sql)
        , ("bindings", Aeson.toJSON bindings)
        , ("time_ms", Aeson.Number (realToFrac timeMs))
        ]

-- | Logger that discards all entries (for production).
silentLogger :: QueryLogger
silentLogger = \_ -> pure ()
