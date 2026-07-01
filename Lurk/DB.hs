module Lurk.DB
    ( -- * Configuration
      DbBackend(..)
    , DbConfig(..)
    , sqliteConfig
    , postgresConfig
      -- * Typeclasses
    , DatabaseProvider(..)
    , FromRow(..)
    , ToRow(..)
    , FromField(..)
    , ToField(..)
      -- * SQL values
    , SqlValue(..)
      -- * Query
    , Query(..)
      -- * Combinators
    , field
      -- * Wrappers
    , Only(..)
      -- * Connection Pool
    , withConnection
    , destroyPool
      -- * Transactions
    , withTransaction
      -- * Errors
    , DbError(..)
    , throwDbError
    , catchDbError
    , handleSqlError
    , formatDbError
      -- * Query Logging
    , QueryLog(..)
    , QueryLogger
    , defaultQueryLogger
    , silentLogger
      -- * Migrations
    , Migration(..)
    , migrate
    , rollback
    , migrations
      -- * Template Haskell
    , deriveFromRow
    , camelToSnake
    , stripPrefix
      -- * QuasiQuoter
    , lurkSQL
      -- * SQLite backend
    , SqliteProvider
    , newSqlitePool
      -- * PostgreSQL backend (stub)
    , PostgresProvider
    , newPostgresPool
    ) where

import Lurk.DB.Core (DatabaseProvider(..), FromRow(..), ToRow(..), FromField(..), ToField(..), SqlValue(..), Query(..), field, Only(..))
import Lurk.DB.Config
import Lurk.DB.Error
import Lurk.DB.Log
import Lurk.DB.Migration
import Lurk.DB.Pool (withConnection, destroyPool)
import Lurk.DB.TH (deriveFromRow, camelToSnake, stripPrefix)
import Lurk.DB.QQ (lurkSQL)
import Lurk.DB.Transaction (withTransaction)
import Lurk.DB.SQLite (SqliteProvider, newSqlitePool)
import Lurk.DB.Postgres (PostgresProvider, newPostgresPool)
