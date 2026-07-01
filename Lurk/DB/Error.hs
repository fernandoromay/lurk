-- | Friendly error types for database operations.
-- Wraps raw exceptions with context messages that PHP devs can understand.
module Lurk.DB.Error
    ( DbError(..)
    , throwDbError
    , catchDbError
    , handleSqlError
    , formatDbError
    ) where

import Control.Exception (Exception, SomeException, catch, throwIO)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Typeable (Typeable)

-- | Database errors with friendly context messages.
data DbError
  = QueryFailed Text       -- ^ Query failed: table 'posts' doesn't exist
  | ConnectionFailed Text  -- ^ Cannot connect to database: file not found
  | MigrationFailed Text   -- ^ Migration 003 failed: near \"SELEC\": syntax error
  | PoolExhausted          -- ^ Connection pool exhausted (timeout after 5s)
  deriving (Show, Typeable)

instance Exception DbError

-- | Throw a DbError.
throwDbError :: DbError -> IO a
throwDbError = throwIO

-- | Catch DbError exceptions.
catchDbError :: IO a -> (DbError -> IO a) -> IO a
catchDbError = catch

-- | Catch SQLite exceptions and wrap them with context.
-- The raw exception message is included for debugging.
handleSqlError :: Text -> IO a -> IO a
handleSqlError context action = action `catch` \e ->
    let msg = context <> ": " <> T.pack (show (e :: SomeException))
    in throwIO (QueryFailed msg)

-- | Format a DbError as a human-readable message.
formatDbError :: DbError -> Text
formatDbError (QueryFailed msg)    = "Query failed: " <> msg
formatDbError (ConnectionFailed msg) = "Cannot connect to database: " <> msg
formatDbError (MigrationFailed msg)  = "Migration failed: " <> msg
formatDbError PoolExhausted          = "Connection pool exhausted (timeout after 5s)"
