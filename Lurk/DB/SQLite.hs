{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Lurk.DB.SQLite
    ( SqliteProvider(..)
    , newSqlitePool
    ) where

import Data.Pool (Pool, withResource, destroyAllResources)
import qualified Data.Pool as Pool
import Database.SQLite.Simple (Connection)
import qualified Database.SQLite.Simple as SQLite
import Lurk.DB.Core (DatabaseProvider(..))
import Lurk.DB.Config (DbConfig(..))

-- | SQLite database provider.
newtype SqliteProvider = SqliteProvider (Pool Connection)

-- | Create a connection pool for SQLite.
newSqlitePool :: DbConfig -> IO SqliteProvider
newSqlitePool cfg = do
    let dbFile' = maybe "app.db" id (dbFile cfg)
        poolSize = dbPoolSize cfg
    pool <- Pool.newPool $ Pool.defaultPoolConfig
        (SQLite.open dbFile')
        SQLite.close
        300
        (fromIntegral poolSize)
    pure (SqliteProvider pool)

instance DatabaseProvider SqliteProvider where
    query (SqliteProvider pool) sql params = withResource pool $ \conn ->
        SQLite.query conn sql params
    execute (SqliteProvider pool) sql params = withResource pool $ \conn ->
        SQLite.execute conn sql params
    closeProvider (SqliteProvider pool) = destroyAllResources pool
