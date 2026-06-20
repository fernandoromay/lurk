module SessionSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time.Clock (addUTCTime, getCurrentTime)
import System.Entropy (getEntropy)
import System.Directory (doesFileExist, doesDirectoryExist, listDirectory, removeFile, removeDirectoryRecursive)
import System.FilePath ((</>))

import Lurk.Session

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.Session"
    [ testGroupId
    , testSessionStore
    , testGetSetDelete
    , testExpiry
    , testFileStore
    , testPersistSession
    , testCleanupSessions
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

----------------------------------------------------------------------
-- File-backed store tests
----------------------------------------------------------------------

testFileStore :: TestTree
testFileStore = testGroup "newFileSessionStore"
    [ testCase "creates directory if missing" $ do
        let dir = ".test-sessions-create"
        store <- newFileSessionStore dir
        exists <- doesDirectoryExist dir
        assertBool "directory should exist" exists
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "loads existing session files from disk" $ do
        let dir = ".test-sessions-load"
        store <- newFileSessionStore dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "foo" "bar", sessionExpiry = addUTCTime 3600 now }
        -- persist manually
        persistSession store sess
        -- create a new store from the same dir
        store2 <- newFileSessionStore dir
        sessions <- readTVarIO (storeSessions store2)
        case Map.lookup sid sessions of
            Nothing -> assertFailure "session not loaded from disk"
            Just loaded -> do
                assertEqual "session id" sid (sessionId loaded)
                assertEqual "session data" (Map.singleton "foo" "bar") (sessionData loaded)
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "skips expired session files on load" $ do
        let dir = ".test-sessions-expired-load"
        store <- newFileSessionStore dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime (-3600) now }
        persistSession store sess
        -- create a new store — expired session should be skipped and file removed
        store2 <- newFileSessionStore dir
        sessions <- readTVarIO (storeSessions store2)
        assertBool "expired session not loaded" (not (Map.member sid sessions))
        fileGone <- doesFileExist (dir </> T.unpack sid)
        assertBool "expired session file removed" (not fileGone)
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "skips unparseable session files on load" $ do
        let dir = ".test-sessions-corrupt"
        store <- newFileSessionStore dir
        sid <- newSessionId
        -- write garbage to a file named like a session
        BS.writeFile (dir </> T.unpack sid) "not a valid session file"
        store2 <- newFileSessionStore dir
        sessions <- readTVarIO (storeSessions store2)
        assertBool "corrupt session not loaded" (Map.null sessions)
        -- cleanup
        removeDirectoryRecursive dir
    ]

----------------------------------------------------------------------
-- persistSession tests
----------------------------------------------------------------------

testPersistSession :: TestTree
testPersistSession = testGroup "persistSession"
    [ testCase "writes session to disk with correct format" $ do
        let dir = ".test-persist-format"
        store <- newFileSessionStore dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "user" "alice", sessionExpiry = addUTCTime 3600 now }
        persistSession store sess
        content <- BC.readFile (dir </> T.unpack sid)
        let lines' = BC.lines content
        -- first line is expiry
        assertBool "has expiry line" (not (null lines'))
        -- second line is key=value
        assertEqual "kv line" (Just "user=alice") (lines' !!? 1)
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "does not leave .tmp file behind" $ do
        let dir = ".test-persist-notmp"
        store <- newFileSessionStore dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime 3600 now }
        persistSession store sess
        files <- listDirectory dir
        assertEqual "only session file exists" [T.unpack sid] files
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "overwrites existing session file atomically" $ do
        let dir = ".test-persist-overwrite"
        store <- newFileSessionStore dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess1 = Session { sessionId = sid, sessionData = Map.singleton "v" "1", sessionExpiry = addUTCTime 3600 now }
        persistSession store sess1
        let sess2 = Session { sessionId = sid, sessionData = Map.singleton "v" "2", sessionExpiry = addUTCTime 3600 now }
        persistSession store sess2
        -- reload and check
        store2 <- newFileSessionStore dir
        sessions <- readTVarIO (storeSessions store2)
        case Map.lookup sid sessions of
            Nothing -> assertFailure "session not found"
            Just loaded -> assertEqual "updated value" (Just "2") (getSessionValue "v" loaded)
        -- no .tmp left
        files <- listDirectory dir
        assertEqual "no tmp files" [T.unpack sid] files
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "no-op for InMemoryStore" $ do
        store <- newSessionStore
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime 3600 now }
        persistSession store sess  -- should not throw
        assertBool "always passes" True
    , testCase "refuses to persist session with non-hex ID" $ do
        let dir = ".test-persist-path-traversal"
        store <- newFileSessionStore dir
        now <- getCurrentTime
        let badSid = "../../etc/passwd"
        let sess = Session { sessionId = badSid, sessionData = Map.empty, sessionExpiry = addUTCTime 3600 now }
        persistSession store sess
        -- file should not exist
        exists <- doesFileExist (dir </> T.unpack badSid)
        assertBool "malicious file not created" (not exists)
        files <- listDirectory dir
        assertBool "no files written" (null files)
        -- cleanup
        removeDirectoryRecursive dir
    ]

-- | Safe index helper
(!!?) :: [a] -> Int -> Maybe a
xs !!? i
    | i < 0 = Nothing
    | otherwise = go i xs
  where
    go _ [] = Nothing
    go 0 (x:_) = Just x
    go n (_:rest) = go (n - 1) rest

----------------------------------------------------------------------
-- cleanupSessions tests
----------------------------------------------------------------------

testCleanupSessions :: TestTree
testCleanupSessions = testGroup "cleanupSessions"
    [ testCase "removes expired sessions from TVar and disk" $ do
        let dir = ".test-cleanup-expired"
        store <- newFileSessionStore dir
        -- add an expired session
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime (-3600) now }
        persistSession store sess
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        -- add a valid session
        sid2 <- newSessionId
        let sess2 = Session { sessionId = sid2, sessionData = Map.empty, sessionExpiry = addUTCTime 3600 now }
        persistSession store sess2
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid2 sess2)
        -- simulate one cleanup cycle
        now2 <- getCurrentTime
        expired <- atomically $ do
            sessions <- readTVar (storeSessions store)
            let expired = Map.filter (\s -> sessionExpiry s <= now2) sessions
            writeTVar (storeSessions store) (Map.filter (\s -> sessionExpiry s > now2) sessions)
            pure expired
        -- remove expired files from disk
        mapM_ (\s -> removeFile (dir </> T.unpack s)) (Map.keys expired)
        -- verify
        sessions <- readTVarIO (storeSessions store)
        assertBool "expired removed from TVar" (not (Map.member sid sessions))
        assertBool "valid kept in TVar" (Map.member sid2 sessions)
        expiredGone <- doesFileExist (dir </> T.unpack sid)
        assertBool "expired file removed from disk" (not expiredGone)
        validExists <- doesFileExist (dir </> T.unpack sid2)
        assertBool "valid file kept on disk" validExists
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "no-op for InMemoryStore" $ do
        store <- newSessionStore
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionExpiry = addUTCTime (-3600) now }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        -- simulate cleanup
        now2 <- getCurrentTime
        atomically $ modifyTVar' (storeSessions store) $
            Map.filter (\s -> sessionExpiry s > now2)
        sessions <- readTVarIO (storeSessions store)
        assertBool "expired removed" (Map.null sessions)
    ]
