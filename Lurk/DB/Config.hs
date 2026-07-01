module Lurk.DB.Config
    ( DbBackend(..)
    , DbConfig(..)
    , sqliteConfig
    , postgresConfig
    ) where

import Data.Text (Text)

-- | Database backend type.
data DbBackend = SQLite | PostgreSQL | MySQL
  deriving (Show, Read, Eq)

-- | Database configuration. All backends share the same record.
-- Use smart constructors for defaults, then override with record update.
data DbConfig = DbConfig
  { dbBackend     :: DbBackend
  , dbFile        :: Maybe FilePath   -- ^ SQLite: path to database file
  , dbHost        :: Maybe Text       -- ^ Postgres/MySQL: hostname
  , dbPort        :: Maybe Int        -- ^ Postgres/MySQL: port
  , dbName        :: Maybe Text       -- ^ Postgres/MySQL: database name
  , dbUser        :: Maybe Text       -- ^ Postgres/MySQL: username
  , dbPassword    :: Maybe Text       -- ^ Postgres/MySQL: password
  , dbPoolSize    :: Int              -- ^ Connection pool size (default: 5)
  , dbAutoMigrate :: Bool             -- ^ Run pending migrations on startup
  } deriving (Show)

-- | Default SQLite config. Points to @app.db@, pool of 5.
--
-- @
-- database = Just sqliteConfig
-- database = Just sqliteConfig { dbFile = Just "my.db", dbAutoMigrate = True }
-- @
sqliteConfig :: DbConfig
sqliteConfig = DbConfig
  { dbBackend     = SQLite
  , dbFile        = Just "app.db"
  , dbHost        = Nothing
  , dbPort        = Nothing
  , dbName        = Nothing
  , dbUser        = Nothing
  , dbPassword    = Nothing
  , dbPoolSize    = 5
  , dbAutoMigrate = False
  }

-- | Default PostgreSQL config. Requires host, database, and user.
--
-- @
-- database = Just (postgresConfig "localhost" "mydb" "admin")
-- database = Just (postgresConfig "localhost" "mydb" "admin") { dbPassword = Just "secret" }
-- @
postgresConfig :: Text -> Text -> Text -> DbConfig
postgresConfig host db user = DbConfig
  { dbBackend     = PostgreSQL
  , dbFile        = Nothing
  , dbHost        = Just host
  , dbPort        = Just 5432
  , dbName        = Just db
  , dbUser        = Just user
  , dbPassword    = Nothing
  , dbPoolSize    = 5
  , dbAutoMigrate = False
  }
