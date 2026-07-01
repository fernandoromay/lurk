{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Lurk.DB.SQLite
    ( SqliteProvider(..)
    , newSqlitePool
    ) where

import Data.Pool (Pool, withResource, destroyAllResources)
import qualified Data.Pool as Pool
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Database.SQLite.Simple (Connection)
import qualified Database.SQLite.Simple as SQLite
import qualified Database.SQLite.Simple.Internal as Internal
import qualified Database.SQLite3 as Direct
import Lurk.DB.Core (DatabaseProvider(..), Query(..), FromRow(..), ToRow(..), SqlValue(..))
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
    query (SqliteProvider pool) q params = withResource pool $ \conn -> do
        let db = Internal.connectionHandle conn
        stmt <- Direct.prepare db (unQuery q)
        bindSqliteParams stmt (toRow params)
        rows <- readAllRows stmt
        Direct.finalize stmt
        pure rows

    execute (SqliteProvider pool) q params = withResource pool $ \conn -> do
        let db = Internal.connectionHandle conn
        stmt <- Direct.prepare db (unQuery q)
        bindSqliteParams stmt (toRow params)
        _ <- Direct.step stmt
        n <- Direct.changes db
        Direct.finalize stmt
        pure (fromIntegral n)

    closeProvider (SqliteProvider pool) = destroyAllResources pool

----------------------------------------------------------------------
-- Bridge: Core.SqlValue → direct-sqlite binding
----------------------------------------------------------------------

bindSqliteParams :: Direct.Statement -> [SqlValue] -> IO ()
bindSqliteParams stmt = mapM_ bind1 . zip [1..]
  where
    bind1 (i, SqlNull)          = Direct.bindNull stmt i
    bind1 (i, SqlInt n)         = Direct.bindInt64 stmt i (fromIntegral n)
    bind1 (i, SqlDouble d)      = Direct.bindDouble stmt i d
    bind1 (i, SqlText t)        = Direct.bindText stmt i t
    bind1 (i, SqlByteString bs) = Direct.bindBlob stmt i bs
    bind1 (i, SqlBool b)        = Direct.bindInt64 stmt i (if b then 1 else 0)
    bind1 (i, SqlLocalTime t)   = Direct.bindText stmt i (T.pack (show t))

----------------------------------------------------------------------
-- Bridge: direct-sqlite SQLData → Core.SqlValue
----------------------------------------------------------------------

sqlDataToSqlValue :: Direct.SQLData -> SqlValue
sqlDataToSqlValue Direct.SQLNull        = SqlNull
sqlDataToSqlValue (Direct.SQLInteger n) = SqlInt (fromIntegral n)
sqlDataToSqlValue (Direct.SQLFloat d)   = SqlDouble d
sqlDataToSqlValue (Direct.SQLText t)    = SqlText t
sqlDataToSqlValue (Direct.SQLBlob bs)   = SqlByteString bs

----------------------------------------------------------------------
-- Read rows using Core.FromRow
----------------------------------------------------------------------

readAllRows :: FromRow row => Direct.Statement -> IO [row]
readAllRows stmt = do
    result <- Direct.step stmt
    case result of
        Direct.Row -> do
            sqlDataList <- Direct.columns stmt
            let values = map sqlDataToSqlValue sqlDataList
            case fromRow values of
                Left err -> error $ "row parse error: " ++ err
                Right row -> (row :) <$> readAllRows stmt
        Direct.Done -> pure []
