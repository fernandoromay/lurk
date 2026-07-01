-- | Generic connection pool operations.
-- Backend-specific pool creation lives in 'Lurk.DB.SQLite', 'Lurk.DB.Postgres', etc.
module Lurk.DB.Pool
    ( Pool
    , withConnection
    , destroyPool
    ) where

import Data.Pool (Pool, destroyAllResources, withResource)
import Lurk.DB.Core (DatabaseProvider)

-- | Run an action with a connection from the pool.
withConnection :: DatabaseProvider db => Pool db -> (db -> IO a) -> IO a
withConnection pool action = withResource pool action

-- | Destroy all connections in the pool.
destroyPool :: Pool db -> IO ()
destroyPool = destroyAllResources
