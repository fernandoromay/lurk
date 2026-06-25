module LogSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Monad (replicateM_)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
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
    , testStandalone
    ]

contentHas :: LBS.ByteString -> T.Text -> Bool
contentHas bs needle = needle `T.isInfixOf` TE.decodeUtf8 (LBS.toStrict bs)

linesOf :: LBS.ByteString -> [LBS.ByteString]
linesOf = filter (not . LBS.null) . LBS.split 10

testWriteLog :: TestTree
testWriteLog = testGroup "writeLog"
    [ testCase "creates file with single entry" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "hello" []
            exists <- doesFileExist path
            assertBool "file exists" exists
            content <- LBS.readFile path
            assertEqual "one entry" 1 (length (linesOf content))
    , testCase "appends multiple entries" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "first" []
            logInfoWith path "second" []
            logInfoWith path "third" []
            content <- LBS.readFile path
            assertEqual "three entries" 3 (length (linesOf content))
            assertBool "has first" (contentHas content "first")
            assertBool "has second" (contentHas content "second")
            assertBool "has third" (contentHas content "third")
    , testCase "does not leave .tmp file behind" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "msg" []
            tmpExists <- doesFileExist (path ++ ".tmp")
            assertBool "no .tmp file" (not tmpExists)
    , testCase "preserves existing content" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            LBS.writeFile path "old line\n"
            logInfoWith path "new entry" []
            content <- LBS.readFile path
            assertBool "has old line" (contentHas content "old line")
            assertBool "has new entry" (contentHas content "new entry")
    , testCase "includes level field" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logWarningWith path "warn msg" []
            content <- LBS.readFile path
            assertBool "has level warning" (contentHas content "warning")
    , testCase "includes message field" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logErrorWith path "error occurred" []
            content <- LBS.readFile path
            assertBool "has message" (contentHas content "error occurred")
    , testCase "includes structured fields" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "with fields" [("key", Aeson.String "val")]
            content <- LBS.readFile path
            assertBool "has key" (contentHas content "key")
            assertBool "has val" (contentHas content "val")
    , testCase "includes timestamp" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "test.log"
            logInfoWith path "timed" []
            content <- LBS.readFile path
            assertBool "has timestamp field" (contentHas content "timestamp")
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
            content <- LBS.readFile path
            assertEqual "all entries present" n (length (linesOf content))
    ]

testLogger :: TestTree
testLogger = testGroup "Logger record"
    [ testCase "newLogger creates log directory" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "sub" </> "app.log"
            logger <- newLogger path
            logInfo logger "from logger" []
            exists <- doesFileExist path
            assertBool "file exists" exists
    , testCase "logDebug works" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "debug.log"
            logger <- newLogger path
            logDebug logger "debug msg" []
            content <- LBS.readFile path
            assertBool "has debug level" (contentHas content "debug")
    , testCase "logWarning works" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "warn.log"
            logger <- newLogger path
            logWarning logger "warn msg" []
            content <- LBS.readFile path
            assertBool "has warning level" (contentHas content "warning")
    , testCase "logError works" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "error.log"
            logger <- newLogger path
            logError logger "error msg" []
            content <- LBS.readFile path
            assertBool "has error level" (contentHas content "error")
    , testCase "logger appends across calls" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "multi.log"
            logger <- newLogger path
            logInfo logger "entry 1" []
            logInfo logger "entry 2" []
            logInfo logger "entry 3" []
            content <- LBS.readFile path
            assertEqual "three entries" 3 (length (linesOf content))
    ]

testStandalone :: TestTree
testStandalone = testGroup "standalone functions"
    [ testCase "logDebugWith works" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "debug.log"
            logDebugWith path "debug" []
            content <- LBS.readFile path
            assertBool "has debug" (contentHas content "debug")
    , testCase "logInfoWith works" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "info.log"
            logInfoWith path "info" []
            content <- LBS.readFile path
            assertBool "has info" (contentHas content "info")
    , testCase "logWarningWith works" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "warn.log"
            logWarningWith path "warn" []
            content <- LBS.readFile path
            assertBool "has warning" (contentHas content "warning")
    , testCase "logErrorWith works" $ do
        withSystemTempDirectory "log-test" $ \tmpDir -> do
            let path = tmpDir </> "error.log"
            logErrorWith path "error" []
            content <- LBS.readFile path
            assertBool "has error" (contentHas content "error")
    ]
