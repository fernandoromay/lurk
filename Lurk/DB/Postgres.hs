{-# LANGUAGE MultiParamTypeClasses #-}
module Lurk.DB.Postgres
    ( PostgresProvider(..)
    , newPostgresPool
    ) where

import Control.Exception (throwIO)
import Lurk.DB.Core (DatabaseProvider(..), Query(..))
import Lurk.DB.Config (DbConfig(..))
import Lurk.DB.Error (DbError(..))

-- | PostgreSQL database provider (stub — not yet implemented).
data PostgresProvider = PostgresProvider

-- | Create a PostgreSQL connection pool (not yet implemented).
newPostgresPool :: DbConfig -> IO PostgresProvider
newPostgresPool _ = throwIO $ ConnectionFailed "PostgreSQL backend not yet implemented. Use SQLite for now."

instance DatabaseProvider PostgresProvider where
    query _ _ _ = throwIO $ ConnectionFailed "PostgreSQL backend not yet implemented"
    execute _ _ _ = throwIO $ ConnectionFailed "PostgreSQL backend not yet implemented"
    closeProvider _ = pure ()
