{-# LANGUAGE ScopedTypeVariables #-}
-- | Transaction support with auto-commit/rollback.
-- Pattern matches Laravel's DB::transaction().
module Lurk.DB.Transaction
    ( withTransaction
    ) where

import Control.Exception (SomeException, catch, throwIO)
import Lurk.DB.Core (DatabaseProvider(..))

-- | Run a block inside a transaction. Auto-commit on success, auto-rollback on exception.
--
-- Note: Each operation within the transaction may use a different connection
-- from the pool. For true single-connection transactions, use backend-specific APIs.
--
-- @
-- withTransaction db $ \db' -> do
--     execute db' "INSERT INTO posts (title) VALUES (?)" (Only "Hello")
--     -- If this throws, the INSERT is rolled back
-- @
withTransaction :: DatabaseProvider db => db -> (db -> IO a) -> IO a
withTransaction db action = do
    execute db "BEGIN TRANSACTION" ()
    result <- action db `catch` (\(e :: SomeException) -> do
        execute db "ROLLBACK" ()
        throwIO e)
    execute db "COMMIT" ()
    pure result
