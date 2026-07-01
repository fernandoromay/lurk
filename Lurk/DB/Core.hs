{-# LANGUAGE MultiParamTypeClasses #-}
module Lurk.DB.Core
    ( -- * Typeclasses
      DatabaseProvider(..)
    , FromRow(..)
    , ToRow(..)
      -- * SQL values
    , SqlValue(..)
      -- * Re-exports
    , Query(..)
    ) where

import Data.ByteString (ByteString)
import Data.Dynamic (Dynamic)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import Database.SQLite.Simple (FromRow(..), ToRow(..), Query(..), field)
import qualified Database.SQLite.Simple as SQLite

-- | A single SQL value (used in Logging, Error, and as a bridge type).
data SqlValue
    = SqlNull
    | SqlInt Int
    | SqlDouble Double
    | SqlText Text
    | SqlByteString ByteString
    | SqlBool Bool
    | SqlLocalTime UTCTime
    | SqlValueUnknown Dynamic
    deriving (Show)

-- | Database provider interface.
-- Implement this for each backend (SQLite, PostgreSQL, MySQL).
--
-- For now, this re-exports sqlite-simple's 'FromRow'/'ToRow' to keep
-- TH-generated instances compatible. When adding Postgres, we'll
-- create adapter newtypes.
class DatabaseProvider db where
    -- | Execute a query and return rows.
    query   :: (SQLite.FromRow row, SQLite.ToRow params) => db -> SQLite.Query -> params -> IO [row]
    -- | Execute a statement and return the number of affected rows.
    execute :: SQLite.ToRow params => db -> SQLite.Query -> params -> IO ()
    -- | Release all connections in the pool.
    closeProvider :: db -> IO ()
