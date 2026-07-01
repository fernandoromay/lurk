-- | Transaction support with auto-commit/rollback.
-- Pattern matches Laravel's DB::transaction().
--
-- @
-- withTransaction pool $ \conn -> do
--     execute conn "INSERT INTO posts (title) VALUES (?)" (Only "Hello")
--     execute conn "UPDATE users SET post_count = post_count + 1 WHERE id = ?" (Only userId)
--     -- If either query throws, both are rolled back automatically
-- @
module Lurk.DB.Transaction
    ( withTransaction
    ) where

import Control.Exception (bracket, SomeException, catch, throwIO)
import Database.SQLite.Simple (Connection, execute_)
import qualified Database.SQLite.Simple as SQLite
import Data.Pool (Pool, withResource)

-- | Run a block inside a transaction. Auto-commit on success, auto-rollback on exception.
--
-- @
-- withTransaction pool $ \conn -> do
--     execute conn "INSERT INTO posts (title) VALUES (?)" (Only "Hello")
--     -- If this throws, the INSERT is rolled back
--     execute conn "UPDATE users SET post_count = post_count + 1 WHERE id = ?" (Only userId)
-- @
--
-- Impossible to forget rollback — the bracket pattern guarantees it.
withTransaction :: Pool Connection -> (Connection -> IO a) -> IO a
withTransaction pool action = withResource pool $ \conn ->
    bracket
        (SQLite.execute_ conn "BEGIN TRANSACTION")
        (\_ -> SQLite.execute_ conn "ROLLBACK" >> pure ())
        (\_ -> do
            result <- action conn
            SQLite.execute_ conn "COMMIT"
            pure result
        )
