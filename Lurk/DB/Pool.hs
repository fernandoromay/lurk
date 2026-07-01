-- | Connection pool management with automatic retry on transient failures.
-- Uses @resource-pool@ for SQLite connections.
module Lurk.DB.Pool
    ( Pool
    , newPool
    , withConnection
    , destroyPool
    ) where

import Control.Exception (throwIO, catch, SomeException)
import qualified Data.Text as T
import Database.SQLite.Simple (Connection, open, close)
import Data.Pool (Pool, destroyAllResources, withResource)
import qualified Data.Pool as Pool
import Lurk.DB.Config (DbConfig(..))

-- | Create a connection pool from configuration.
-- For SQLite, the pool creates connections to the configured file.
newPool :: DbConfig -> IO (Pool Connection)
newPool cfg = do
    let dbFile' = maybe "app.db" id (dbFile cfg)
        poolSize = maybe 5 id (dbPoolSize cfg)
    Pool.newPool $ Pool.defaultPoolConfig (open dbFile') close 300 (fromIntegral poolSize)

-- | Run an action with a connection from the pool.
-- Retries once on transient connection failures (file locked, etc.).
withConnection :: Pool Connection -> (Connection -> IO a) -> IO a
withConnection pool action = withResource pool tryAction
  where
    tryAction conn = action conn `catch` retryOnTransient conn

    retryOnTransient conn ex = do
        let msg = show (ex :: SomeException)
        if any (`T.isInfixOf` T.pack msg) transientErrors
            then action conn
            else throwIO ex

    transientErrors =
        [ "database is locked"
        , "busy"
        , "SQLITE_BUSY"
        , "SQLITE_LOCKED"
        ]

-- | Destroy all connections in the pool.
destroyPool :: Pool Connection -> IO ()
destroyPool = destroyAllResources
