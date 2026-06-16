module SessionSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Concurrent.STM
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time.Clock (addUTCTime, getCurrentTime)
import System.Entropy (getEntropy)

import Lurk.Session

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.Session"
    [ testGroupId
    , testSessionStore
    , testGetSetDelete
    , testExpiry
    ]

testGroupId :: TestTree
testGroupId = testGroup "newSessionId"
    [ testCase "returns 48-char hex string (24 bytes)" $ do
        sid <- newSessionId
        assertBool ("expected 48 chars, got " ++ show (T.length sid)) (T.length sid == 48)
    , testCase "only contains hex characters" $ do
        sid <- newSessionId
        assertBool ("non-hex chars in: " ++ T.unpack sid) (T.all (\c -> c `elem` ("0123456789abcdef" :: String)) sid)
    , testCase "generates unique IDs" $ do
        s1 <- newSessionId
        s2 <- newSessionId
        assertBool "IDs should differ" (s1 /= s2)
    ]

testSessionStore :: TestTree
testSessionStore = testGroup "newSessionStore"
    [ testCase "creates empty store" $ do
        store <- newSessionStore
        sessions <- readTVarIO (storeSessions store)
        assertBool "store should be empty" (Map.null sessions)
    ]

testGetSetDelete :: TestTree
testGetSetDelete = testGroup "get/set/delete session values"
    [ testCase "set and get a value" $ do
        store <- newSessionStore
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime 3600 now }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        -- set value
        sessions <- readTVarIO (storeSessions store)
        let Just s = Map.lookup sid sessions
        let updated = s { sessionData = Map.insert "key" "value" (sessionData s) }
        atomically $ writeTVar (storeSessions store) (Map.insert sid updated Map.empty)

        -- get value
        sessions' <- readTVarIO (storeSessions store)
        let Just s' = Map.lookup sid sessions'
        assertEqual "should retrieve set value" (Just "value") (getSessionValue "key" s')
    , testCase "delete a value" $ do
        store <- newSessionStore
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "k" "v", sessionExpiry = addUTCTime 3600 now }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        sessions <- readTVarIO (storeSessions store)
        let Just s = Map.lookup sid sessions
        let updated = s { sessionData = Map.delete "k" (sessionData s) }
        atomically $ writeTVar (storeSessions store) (Map.insert sid updated Map.empty)

        sessions' <- readTVarIO (storeSessions store)
        let Just s' = Map.lookup sid sessions'
        assertEqual "should be Nothing after delete" Nothing (getSessionValue "k" s')
    , testCase "get missing key returns Nothing" $ do
        store <- newSessionStore
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime 3600 now }
        assertEqual "missing key" Nothing (getSessionValue "nope" sess)
    ]

testExpiry :: TestTree
testExpiry = testGroup "session expiry"
    [ testCase "expired session is filtered by cleanup logic" $ do
        store <- newSessionStore
        sid <- newSessionId
        now <- getCurrentTime
        -- session that expired 1 hour ago
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime (-3600) now }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        -- simulate cleanup
        atomically $ modifyTVar' (storeSessions store) $
            Map.filter (\s -> sessionExpiry s > now)

        sessions <- readTVarIO (storeSessions store)
        assertBool "expired session removed" (Map.null sessions)
    , testCase "valid session survives cleanup" $ do
        store <- newSessionStore
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime 3600 now }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        atomically $ modifyTVar' (storeSessions store) $
            Map.filter (\s -> sessionExpiry s > now)

        sessions <- readTVarIO (storeSessions store)
        assertBool "valid session kept" (Map.member sid sessions)
    ]
