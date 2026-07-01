module Lurk.DB.Config
    ( DbBackend(..)
    , DbConfig(..)
    , dbConfig
    ) where

import Data.Text (Text)
import qualified Data.Text as T

-- | Database backend type.
data DbBackend = SQLite | PostgreSQL | MySQL
  deriving (Show, Read, Eq)

-- | Database configuration.
data DbConfig = DbConfig
  { dbBackend     :: DbBackend
  , dbFile        :: Maybe FilePath   -- ^ SQLite: path to database file (e.g., \"app.db\")
  , dbHost        :: Maybe Text       -- ^ Postgres/MySQL: hostname
  , dbPort        :: Maybe Int        -- ^ Postgres/MySQL: port
  , dbName        :: Maybe Text       -- ^ Postgres/MySQL: database name
  , dbUser        :: Maybe Text       -- ^ Postgres/MySQL: username
  , dbPassword    :: Maybe Text       -- ^ Postgres/MySQL: password
  , dbPoolSize    :: Maybe Int        -- ^ Connection pool size (default: 5)
  , dbAutoMigrate :: Bool             -- ^ Run pending migrations on startup
  } deriving (Show)

-- | Default config with SQLite backend.
dbConfig :: DbConfig
dbConfig = DbConfig
  { dbBackend     = SQLite
  , dbFile        = Just "app.db"
  , dbHost        = Nothing
  , dbPort        = Nothing
  , dbName        = Nothing
  , dbUser        = Nothing
  , dbPassword    = Nothing
  , dbPoolSize    = Just 5
  , dbAutoMigrate = False
  }
