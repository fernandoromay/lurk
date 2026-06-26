module LogSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Monad (replicateM_)
import Data.Aeson qualified as Aeson
import Data.ByteString.Char8 qualified as BC
import Data.Text qualified as T
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Lurk.Log

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.Log"
    [ testWriteLog
    , testLogger
    ]

----------------------------------------------------------------------
-- writeLog TESTS
----------------------------------------------------------------------

testWriteLog :: TestTree
testWriteLog = testGroup "writeLog"
    [ testCase "single entry creates file with one line" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "hello" []
            content <- BC.readFile path
            let lines' = filter (not . BC.null) (BC.lines content)
            assertEqual "1 entry" 1 (length lines')
    , testCase "entries accumulate across writes" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "first" []
            logInfoWith path "second" []
            logWarningWith path "third" []
            content <- BC.readFile path
            let lines' = filter (not . BC.null) (BC.lines content)
            assertEqual "3 entries" 3 (length lines')
    , testCase "log directory created automatically" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "sub" </> "deep" </> "test.log"
            logInfoWith path "hello" []
            exists <- doesFileExist path
            assertBool "file exists" exists
    , testCase "entry contains level and timestamp" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "test message" []
            content <- BC.readFile path
            assertBool "has level" ("level" `BC.isInfixOf` content)
            assertBool "has timestamp" ("timestamp" `BC.isInfixOf` content)
    , testCase "structured fields are included" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "with fields" [("key", Aeson.String "value")]
            content <- BC.readFile path
            assertBool "has field" ("key" `BC.isInfixOf` content)
    , testCase "concurrent writes preserve all entries" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "race.log"
            let n = 50
            done <- newEmptyMVar
            mapM_ (\i ->
                forkIO $ do
                    logInfoWith path (T.pack $ "entry-" ++ show i) []
                    putMVar done ()) [1..n]
            replicateM_ n (takeMVar done)
            content <- BC.readFile path
            let lines' = filter (not . BC.null) (BC.lines content)
            assertEqual "all entries present" n (length lines')
    ]

----------------------------------------------------------------------
-- Logger TESTS
----------------------------------------------------------------------

testLogger :: TestTree
testLogger = testGroup "Logger"
    [ testCase "logger accumulates entries" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "logger.log"
            logger <- newLogger path
            logInfo logger "from logger" []
            logWarning logger "warning msg" []
            content <- BC.readFile path
            let lines' = filter (not . BC.null) (BC.lines content)
            assertEqual "2 entries" 2 (length lines')
    ]
