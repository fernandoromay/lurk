{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}
module DBSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import Database.SQLite.Simple (Only(..), query_, query, execute_, execute)
import qualified Database.SQLite.Simple as SQLite
import System.Directory (removeFile, doesFileExist, createDirectoryIfMissing)
import System.IO.Temp (withSystemTempDirectory)
import Control.Exception (SomeException, catch)

import Lurk.DB.TH (camelToSnake, stripPrefix)
import Lurk.DB.QQ (lurkSQL)
import Lurk.DB.Config (DbConfig(..), DbBackend(..), dbConfig)
import Lurk.DB.Pool (Pool, newPool, withConnection, destroyPool)
import Lurk.DB.Transaction (withTransaction)
import Lurk.DB.Migration (migrate, rollback, ensureMigrationsTable)

----------------------------------------------------------------------
-- camelToSnake tests
----------------------------------------------------------------------
testCamelToSnakeSimple :: Assertion
testCamelToSnakeSimple = camelToSnake "postTitle" @?= "post_title"

testCamelToSnakeAllLower :: Assertion
testCamelToSnakeAllLower = camelToSnake "title" @?= "title"

testCamelToSnakeAllUpper :: Assertion
testCamelToSnakeAllUpper = camelToSnake "URL" @?= "_u_r_l"

testCamelToSnakeMultipleWords :: Assertion
testCamelToSnakeMultipleWords = camelToSnake "postCreatedAt" @?= "post_created_at"

----------------------------------------------------------------------
-- stripPrefix tests
----------------------------------------------------------------------
testStripPrefixSimple :: Assertion
testStripPrefixSimple = stripPrefix "Post" "postTitle" @?= "Title"

testStripPrefixNoMatch :: Assertion
testStripPrefixNoMatch = stripPrefix "User" "postTitle" @?= "postTitle"

testStripPrefixExact :: Assertion
testStripPrefixExact = stripPrefix "Post" "post" @?= ""

----------------------------------------------------------------------
-- lurkSQL QQ tests
----------------------------------------------------------------------
testLurkSQLNoParams :: Assertion
testLurkSQLNoParams = do
    let (sql, ()) = [lurkSQL|SELECT 1|] :: (Text, ())
    sql @?= "SELECT 1"

testLurkSQLSingleParam :: Assertion
testLurkSQLSingleParam = do
    let postId = 42 :: Int
        (sql, params) = [lurkSQL|SELECT * FROM posts WHERE id = {{postId}}|] :: (Text, (Int, ()))
    sql @?= "SELECT * FROM posts WHERE id = ?"
    params @?= (42, ())

testLurkSQLMultipleParams :: Assertion
testLurkSQLMultipleParams = do
    let postId = 1 :: Int
        title = "Hello" :: Text
        (sql, params) = [lurkSQL|SELECT * FROM posts WHERE id = {{postId}} AND title = {{title}}|] :: (Text, (Int, Text))
    sql @?= "SELECT * FROM posts WHERE id = ? AND title = ?"
    params @?= (1, "Hello")

testLurkSQLInsert :: Assertion
testLurkSQLInsert = do
    let title = "My Post" :: Text
        (sql, params) = [lurkSQL|INSERT INTO posts (title) VALUES ({{title}})|] :: (Text, (Text, ()))
    sql @?= "INSERT INTO posts (title) VALUES (?)"
    params @?= ("My Post", ())

----------------------------------------------------------------------
-- Pool and query tests (using temp SQLite DB)
----------------------------------------------------------------------
withTestDB :: (Pool SQLite.Connection -> IO a) -> IO a
withTestDB action = withSystemTempDirectory "lurk-test" $ \dir -> do
    let dbPath = dir ++ "/test.db"
    pool <- newPool dbConfig { dbFile = Just dbPath }
    withConnection pool $ \conn ->
        SQLite.execute_ conn "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL, content TEXT)"
    result <- action pool
    destroyPool pool
    pure result

testPoolInsertAndQuery :: Assertion
testPoolInsertAndQuery = withTestDB $ \pool -> do
    withConnection pool $ \conn -> do
        execute conn "INSERT INTO posts (title, content) VALUES (?, ?)" ("Hello" :: Text, "World" :: Text)
        rows <- query_ conn "SELECT id, title, content FROM posts" :: IO [(Int, Text, Text)]
        length rows @?= 1
        let (pid, t, c) = head rows
        t @?= "Hello"
        c @?= "World"

testPoolMultipleRows :: Assertion
testPoolMultipleRows = withTestDB $ \pool -> do
    withConnection pool $ \conn -> do
        execute conn "INSERT INTO posts (title, content) VALUES (?, ?)" ("Post 1" :: Text, "Content 1" :: Text)
        execute conn "INSERT INTO posts (title, content) VALUES (?, ?)" ("Post 2" :: Text, "Content 2" :: Text)
        execute conn "INSERT INTO posts (title, content) VALUES (?, ?)" ("Post 3" :: Text, "Content 3" :: Text)
        rows <- query_ conn "SELECT title FROM posts ORDER BY id" :: IO [Only Text]
        map fromOnly rows @?= ["Post 1", "Post 2", "Post 3"]

----------------------------------------------------------------------
-- Transaction tests
----------------------------------------------------------------------
testTransactionCommit :: Assertion
testTransactionCommit = withTestDB $ \pool -> do
    withTransaction pool $ \conn -> do
        execute conn "INSERT INTO posts (title, content) VALUES (?, ?)" ("Committed" :: Text, "" :: Text)
    withConnection pool $ \conn -> do
        rows <- query_ conn "SELECT title FROM posts" :: IO [Only Text]
        map fromOnly rows @?= ["Committed"]

testTransactionRollback :: Assertion
testTransactionRollback = withTestDB $ \pool -> do
    (withTransaction pool (\conn -> do
        execute conn "INSERT INTO posts (title, content) VALUES (?, ?)" ("Should Rollback" :: Text, "" :: Text)
        error "force rollback") :: IO ()) `catch` (\(_ :: SomeException) -> pure ())
    withConnection pool $ \conn -> do
        rows <- query_ conn "SELECT title FROM posts" :: IO [Only Text]
        length rows @?= 0

----------------------------------------------------------------------
-- Migration tests
----------------------------------------------------------------------
testMigrationCreatesTable :: Assertion
testMigrationCreatesTable = withSystemTempDirectory "lurk-migrate-test" $ \dir -> do
    let dbPath = dir ++ "/test.db"
        migrationsDir = dir ++ "/migrations"
    createDirectoryIfMissing True migrationsDir
    writeFile (migrationsDir ++ "/001_create_posts.sql")
        "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL);"
    pool <- newPool dbConfig { dbFile = Just dbPath }
    migrate pool migrationsDir
    withConnection pool $ \conn -> do
        execute conn "INSERT INTO posts (title) VALUES (?)" (Only ("test" :: Text))
        rows <- query_ conn "SELECT title FROM posts" :: IO [Only Text]
        map fromOnly rows @?= ["test"]
    destroyPool pool

----------------------------------------------------------------------
-- Test group
----------------------------------------------------------------------
tests :: TestTree
tests = testGroup "DB"
    [ testGroup "camelToSnake"
        [ testCase "simple camelCase" testCamelToSnakeSimple
        , testCase "all lowercase" testCamelToSnakeAllLower
        , testCase "all uppercase" testCamelToSnakeAllUpper
        , testCase "multiple words" testCamelToSnakeMultipleWords
        ]
    , testGroup "stripPrefix"
        [ testCase "strips matching prefix" testStripPrefixSimple
        , testCase "no match returns original" testStripPrefixNoMatch
        , testCase "exact match returns empty" testStripPrefixExact
        ]
    , testGroup "lurkSQL"
        [ testCase "no parameters" testLurkSQLNoParams
        , testCase "single parameter" testLurkSQLSingleParam
        , testCase "multiple parameters" testLurkSQLMultipleParams
        , testCase "insert statement" testLurkSQLInsert
        ]
    , testGroup "Pool"
        [ testCase "insert and query" testPoolInsertAndQuery
        , testCase "multiple rows" testPoolMultipleRows
        ]
    , testGroup "Transaction"
        [ testCase "commit persists data" testTransactionCommit
        , testCase "rollback discards data" testTransactionRollback
        ]
    , testGroup "Migration"
        [ testCase "creates table from SQL file" testMigrationCreatesTable
        ]
    ]
