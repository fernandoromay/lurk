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
import Data.Time.Format (formatTime, defaultTimeLocale)
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
    , testDestroySession
    , testISO8601Roundtrip
    , testRollingExpiration
    , testStrictExpiration
    , testRollingEndToEnd
    , testMaxAgeNeverExtended
    , testBothExpirations
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
        store <- newSessionStore Nothing Nothing
        sessions <- readTVarIO (storeSessions store)
        assertBool "store should be empty" (Map.null sessions)
    ]

testGetSetDelete :: TestTree
testGetSetDelete = testGroup "get/set/delete session values"
    [ testCase "set and get a value" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
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
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "k" "v", sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        sessions <- readTVarIO (storeSessions store)
        let Just s = Map.lookup sid sessions
        let updated = s { sessionData = Map.delete "k" (sessionData s) }
        atomically $ writeTVar (storeSessions store) (Map.insert sid updated Map.empty)

        sessions' <- readTVarIO (storeSessions store)
        let Just s' = Map.lookup sid sessions'
        assertEqual "should be Nothing after delete" Nothing (getSessionValue "k" s')
    , testCase "get missing key returns Nothing" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        assertEqual "missing key" Nothing (getSessionValue "nope" sess)
    ]

testExpiry :: TestTree
testExpiry = testGroup "session expiry"
    [ testCase "expired session is filtered by cleanup logic" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        -- session that expired 1 hour ago
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime (-3600) now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        -- simulate cleanup
        atomically $ modifyTVar' (storeSessions store) $
            Map.filter (not . isSessionExpired now)

        sessions <- readTVarIO (storeSessions store)
        assertBool "expired session removed" (Map.null sessions)
    , testCase "valid session survives cleanup" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        atomically $ modifyTVar' (storeSessions store) $
            Map.filter (not . isSessionExpired now)

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
        store <- newFileSessionStore Nothing Nothing dir
        exists <- doesDirectoryExist dir
        assertBool "directory should exist" exists
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "loads existing session files from disk" $ do
        let dir = ".test-sessions-load"
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "foo" "bar", sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        -- persist manually
        persistSession store sess
        -- create a new store from the same dir
        store2 <- newFileSessionStore Nothing Nothing dir
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
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime (-3600) now), sessionIdleExp = Nothing }
        persistSession store sess
        -- create a new store -- expired session should be skipped and file removed
        store2 <- newFileSessionStore Nothing Nothing dir
        sessions <- readTVarIO (storeSessions store2)
        assertBool "expired session not loaded" (not (Map.member sid sessions))
        fileGone <- doesFileExist (dir </> T.unpack sid)
        assertBool "expired session file removed" (not fileGone)
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "skips unparseable session files on load" $ do
        let dir = ".test-sessions-corrupt"
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        -- write garbage to a file named like a session
        BS.writeFile (dir </> T.unpack sid) "not a valid session file"
        store2 <- newFileSessionStore Nothing Nothing dir
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
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "user" "alice", sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess
        content <- BC.readFile (dir </> T.unpack sid)
        let lines' = BC.lines content
        -- first line is absolute expiry, second is idle expiry
        assertBool "has expiry lines" (length lines' >= 2)
        -- third line is key=value
        assertEqual "kv line" (Just "user=alice") (lines' !!? 2)
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "does not leave .tmp file behind" $ do
        let dir = ".test-persist-notmp"
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess
        files <- listDirectory dir
        assertEqual "only session file exists" [T.unpack sid] files
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "overwrites existing session file atomically" $ do
        let dir = ".test-persist-overwrite"
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess1 = Session { sessionId = sid, sessionData = Map.singleton "v" "1", sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess1
        let sess2 = Session { sessionId = sid, sessionData = Map.singleton "v" "2", sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess2
        -- reload and check
        store2 <- newFileSessionStore Nothing Nothing dir
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
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess  -- should not throw
        assertBool "always passes" True
    , testCase "refuses to persist session with non-hex ID" $ do
        let dir = ".test-persist-path-traversal"
        store <- newFileSessionStore Nothing Nothing dir
        now <- getCurrentTime
        let badSid = "../../etc/passwd"
        let sess = Session { sessionId = badSid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
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
        store <- newFileSessionStore Nothing Nothing dir
        -- add an expired session
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime (-3600) now), sessionIdleExp = Nothing }
        persistSession store sess
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        -- add a valid session
        sid2 <- newSessionId
        let sess2 = Session { sessionId = sid2, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess2
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid2 sess2)
        -- simulate one cleanup cycle
        now2 <- getCurrentTime
        expired <- atomically $ do
            sessions <- readTVar (storeSessions store)
            let expired = Map.filter (isSessionExpired now2) sessions
            writeTVar (storeSessions store) (Map.filter (not . isSessionExpired now2) sessions)
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
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime (-3600) now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        -- simulate cleanup
        now2 <- getCurrentTime
        atomically $ modifyTVar' (storeSessions store) $
            Map.filter (not . isSessionExpired now2)
        sessions <- readTVarIO (storeSessions store)
        assertBool "expired removed" (Map.null sessions)
    ]

----------------------------------------------------------------------
-- destroySession tests
----------------------------------------------------------------------

testDestroySession :: TestTree
testDestroySession = testGroup "destroySession"
    [ testCase "removes session from TVar" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "k" "v", sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        destroySession store sid
        sessions <- readTVarIO (storeSessions store)
        assertBool "session removed" (not (Map.member sid sessions))
    , testCase "removes session file from disk (FileStore)" $ do
        let dir = ".test-destroy-file"
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess
        exists1 <- doesFileExist (dir </> T.unpack sid)
        assertBool "file exists before destroy" exists1
        destroySession store sid
        exists2 <- doesFileExist (dir </> T.unpack sid)
        assertBool "file removed after destroy" (not exists2)
        -- also verify removed from TVar
        sessions <- readTVarIO (storeSessions store)
        assertBool "session removed from TVar" (not (Map.member sid sessions))
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "no-op for non-existent session" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        destroySession store sid  -- should not throw
        assertBool "always passes" True
    ]

----------------------------------------------------------------------
-- ISO 8601 roundtrip tests
----------------------------------------------------------------------

testISO8601Roundtrip :: TestTree
testISO8601Roundtrip = testGroup "ISO 8601 roundtrip"
    [ testCase "persist and reload preserves exact timestamps" $ do
        let dir = ".test-iso8601-roundtrip"
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        let absExp = Just (addUTCTime 3600 now)
            idleExp = Just (addUTCTime 1800 now)
        let sess = Session { sessionId = sid, sessionData = Map.singleton "x" "y"
                           , sessionAbsoluteExp = absExp, sessionIdleExp = idleExp }
        persistSession store sess
        -- reload
        store2 <- newFileSessionStore Nothing Nothing dir
        sessions <- readTVarIO (storeSessions store2)
        case Map.lookup sid sessions of
            Nothing -> assertFailure "session not found"
            Just loaded -> do
                -- Compare via formatted string (ISO 8601 format truncates to seconds)
                let fmt = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"
                assertEqual "absolute exp" (fmt <$> absExp) (fmt <$> sessionAbsoluteExp loaded)
                assertEqual "idle exp" (fmt <$> idleExp) (fmt <$> sessionIdleExp loaded)
        -- cleanup
        removeDirectoryRecursive dir
    , testCase "empty expiry lines parse as Nothing" $ do
        let dir = ".test-iso8601-empty"
        store <- newFileSessionStore Nothing Nothing dir
        sid <- newSessionId
        now <- getCurrentTime
        -- session with only absolute, no idle
        let sess = Session { sessionId = sid, sessionData = Map.empty
                           , sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        persistSession store sess
        -- read raw file
        content <- BC.readFile (dir </> T.unpack sid)
        let lines' = BC.lines content
        -- second line (idle) should be empty
        assertEqual "idle line empty" "" (BC.unpack (lines' !! 1))
        -- cleanup
        removeDirectoryRecursive dir
    ]

----------------------------------------------------------------------
-- Rolling expiration tests
----------------------------------------------------------------------

testRollingExpiration :: TestTree
testRollingExpiration = testGroup "rolling expiration"
    [ testCase "refreshIdleExp updates idle timestamp" $ do
        now <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Nothing
                           , sessionIdleExp = Just (addUTCTime 100 now) }
        let refreshed = refreshIdleExp (Just 300) now sess
        assertEqual "idle exp updated" (Just (addUTCTime 300 now)) (sessionIdleExp refreshed)
        assertEqual "abs exp unchanged" Nothing (sessionAbsoluteExp refreshed)
    , testCase "refreshIdleExp is no-op when timeout is Nothing" $ do
        now <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Nothing
                           , sessionIdleExp = Just (addUTCTime 100 now) }
        let refreshed = refreshIdleExp Nothing now sess
        assertEqual "idle exp unchanged" (sessionIdleExp sess) (sessionIdleExp refreshed)
    , testCase "session with idle expiry only is expired when idle passes" $ do
        now <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Nothing
                           , sessionIdleExp = Just (addUTCTime (-10) now) }
        assertBool "expired" (isSessionExpired now sess)
    , testCase "session with idle expiry only is valid when idle is future" $ do
        now <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Nothing
                           , sessionIdleExp = Just (addUTCTime 300 now) }
        assertBool "not expired" (not (isSessionExpired now sess))
    , testCase "newSessionExps with only idle timeout" $ do
        now <- getCurrentTime
        let (absExp, idleExp) = newSessionExps Nothing (Just 600) now
        assertEqual "abs follows idle" (Just (addUTCTime 600 now)) absExp
        assertEqual "idle set" (Just (addUTCTime 600 now)) idleExp
    ]

----------------------------------------------------------------------
-- Strict expiration tests
----------------------------------------------------------------------

testStrictExpiration :: TestTree
testStrictExpiration = testGroup "strict expiration"
    [ testCase "session with absolute expiry only is expired when absolute passes" $ do
        now <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Just (addUTCTime (-10) now)
                           , sessionIdleExp = Nothing }
        assertBool "expired" (isSessionExpired now sess)
    , testCase "session with absolute expiry only is valid when absolute is future" $ do
        now <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Just (addUTCTime 3600 now)
                           , sessionIdleExp = Nothing }
        assertBool "not expired" (not (isSessionExpired now sess))
    , testCase "newSessionExps with only max age" $ do
        now <- getCurrentTime
        let (absExp, idleExp) = newSessionExps (Just 86400) Nothing now
        assertEqual "abs set" (Just (addUTCTime 86400 now)) absExp
        assertEqual "idle is Nothing" Nothing idleExp
    , testCase "newSessionExps with both set" $ do
        now <- getCurrentTime
        let (absExp, idleExp) = newSessionExps (Just 2592000) (Just 604800) now
        assertEqual "abs from max age" (Just (addUTCTime 2592000 now)) absExp
        assertEqual "idle from idle timeout" (Just (addUTCTime 604800 now)) idleExp
    , testCase "newSessionExps defaults to 24h when both Nothing" $ do
        now <- getCurrentTime
        let (absExp, idleExp) = newSessionExps Nothing Nothing now
        assertEqual "abs defaults to 24h" (Just (addUTCTime 86400 now)) absExp
        assertEqual "idle is Nothing" Nothing idleExp
    , testCase "session with both expiries is expired if either passes" $ do
        now <- getCurrentTime
        -- absolute expired, idle valid
        let sess1 = Session { sessionId = "test", sessionData = Map.empty
                            , sessionAbsoluteExp = Just (addUTCTime (-10) now)
                            , sessionIdleExp = Just (addUTCTime 3600 now) }
        assertBool "expired (abs passed)" (isSessionExpired now sess1)
        -- absolute valid, idle expired
        let sess2 = Session { sessionId = "test", sessionData = Map.empty
                            , sessionAbsoluteExp = Just (addUTCTime 3600 now)
                            , sessionIdleExp = Just (addUTCTime (-10) now) }
        assertBool "expired (idle passed)" (isSessionExpired now sess2)
    ]

----------------------------------------------------------------------
-- Rolling end-to-end: simulates middleware refresh on each request
----------------------------------------------------------------------

testRollingEndToEnd :: TestTree
testRollingEndToEnd = testGroup "rolling expiration end-to-end"
    [ testCase "simulated requests keep session alive" $ do
        store <- newSessionStore Nothing (Just 60)  -- 60s idle
        -- Simulate session creation (as middleware would)
        now0 <- getCurrentTime
        sid <- newSessionId
        let (absExp, idleExp) = newSessionExps Nothing (Just 60) now0
        let sess = Session { sessionId = sid, sessionData = Map.empty
                           , sessionAbsoluteExp = absExp, sessionIdleExp = idleExp }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        -- Request 1 at t+10s: refresh idle to t+10+60 = t+70
        let simulated1 = addUTCTime 10 now0
        sessions1 <- readTVarIO (storeSessions store)
        let Just s1 = Map.lookup sid sessions1
        assertBool "req1: not expired" (not (isSessionExpired simulated1 s1))
        let refreshed1 = refreshIdleExp (Just 60) simulated1 s1
        assertEqual "req1: idle = t+70" (Just (addUTCTime 70 now0)) (sessionIdleExp refreshed1)
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid refreshed1)

        -- Request 2 at t+20s: refresh idle to t+20+60 = t+80
        let simulated2 = addUTCTime 20 now0
        sessions2 <- readTVarIO (storeSessions store)
        let Just s2 = Map.lookup sid sessions2
        assertEqual "req2: idle = t+70" (Just (addUTCTime 70 now0)) (sessionIdleExp s2)
        assertBool "req2: not expired" (not (isSessionExpired simulated2 s2))
        let refreshed2 = refreshIdleExp (Just 60) simulated2 s2
        assertEqual "req2: idle = t+80" (Just (addUTCTime 80 now0)) (sessionIdleExp refreshed2)
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid refreshed2)

        -- Request 3 at t+50s: refresh idle to t+50+60 = t+110
        let simulated3 = addUTCTime 50 now0
        sessions3 <- readTVarIO (storeSessions store)
        let Just s3 = Map.lookup sid sessions3
        assertEqual "req3: idle = t+80" (Just (addUTCTime 80 now0)) (sessionIdleExp s3)
        assertBool "req3: not expired" (not (isSessionExpired simulated3 s3))
        let refreshed3 = refreshIdleExp (Just 60) simulated3 s3
        assertEqual "req3: idle = t+110" (Just (addUTCTime 110 now0)) (sessionIdleExp refreshed3)
    , testCase "session expires if no request within idle window" $ do
        store <- newSessionStore Nothing (Just 60)  -- 60s idle
        now0 <- getCurrentTime
        sid <- newSessionId
        let (absExp, idleExp) = newSessionExps Nothing (Just 60) now0
        let sess = Session { sessionId = sid, sessionData = Map.empty
                           , sessionAbsoluteExp = absExp, sessionIdleExp = idleExp }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        -- Request at t+10s: refresh
        let simulated1 = addUTCTime 10 now0
        sessions1 <- readTVarIO (storeSessions store)
        let Just s1 = Map.lookup sid sessions1
        let refreshed1 = refreshIdleExp (Just 60) simulated1 s1
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid refreshed1)

        -- No request for 61s. At t+71s: idle was t+70, now t+71 -> expired
        let simulated2 = addUTCTime 71 now0
        sessions2 <- readTVarIO (storeSessions store)
        let Just s2 = Map.lookup sid sessions2
        assertBool "expired after idle window" (isSessionExpired simulated2 s2)
    ]

----------------------------------------------------------------------
-- Max age is never extended by rolling
----------------------------------------------------------------------

testMaxAgeNeverExtended :: TestTree
testMaxAgeNeverExtended = testGroup "max age never extended"
    [ testCase "absolute expiry stays fixed across refreshes" $ do
        store <- newSessionStore (Just 3600) (Just 60)  -- 1h abs, 60s idle
        now0 <- getCurrentTime
        sid <- newSessionId
        let (absExp, idleExp) = newSessionExps (Just 3600) (Just 60) now0
        let sess = Session { sessionId = sid, sessionData = Map.empty
                           , sessionAbsoluteExp = absExp, sessionIdleExp = idleExp }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        -- Simulate 100 requests, each refreshing idle
        let simulateRequest t = do
                sessions <- readTVarIO (storeSessions store)
                let Just s = Map.lookup sid sessions
                let refreshed = refreshIdleExp (Just 60) t s
                atomically $ modifyTVar' (storeSessions store) (Map.insert sid refreshed)

        mapM_ (\i -> simulateRequest (addUTCTime (fromIntegral i) now0)) [1..100]

        -- Absolute expiry must still be exactly now0 + 3600
        sessions <- readTVarIO (storeSessions store)
        let Just final = Map.lookup sid sessions
        assertEqual "absolute expiry unchanged after 100 refreshes"
            (Just (addUTCTime 3600 now0)) (sessionAbsoluteExp final)
        -- Idle expiry should be now0 + 100 + 60 = now0 + 160
        assertEqual "idle expiry rolled to t+160"
            (Just (addUTCTime 160 now0)) (sessionIdleExp final)
    , testCase "session dies at absolute expiry even if idle was just refreshed" $ do
        now0 <- getCurrentTime
        -- Create session with 10s absolute, 60s idle
        sid <- newSessionId
        let sess = Session { sessionId = sid, sessionData = Map.empty
                           , sessionAbsoluteExp = Just (addUTCTime 10 now0)
                           , sessionIdleExp = Just (addUTCTime 60 now0) }

        -- Refresh at t+9s (1s before abs expiry)
        let refreshed = refreshIdleExp (Just 60) (addUTCTime 9 now0) sess
        assertEqual "idle rolled" (Just (addUTCTime 69 now0)) (sessionIdleExp refreshed)

        -- At t+11s: absolute expired, even though idle is still valid
        assertBool "expired at absolute" (isSessionExpired (addUTCTime 11 now0) refreshed)
    ]

----------------------------------------------------------------------
-- Both expirations together
----------------------------------------------------------------------

testBothExpirations :: TestTree
testBothExpirations = testGroup "both expirations together"
    [ testCase "idle expires first, absolute still valid -> session dies" $ do
        now0 <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Just (addUTCTime 3600 now0)  -- 1h
                           , sessionIdleExp = Just (addUTCTime 60 now0) }      -- 60s
        -- At t+61s: idle expired, absolute valid
        assertBool "expired" (isSessionExpired (addUTCTime 61 now0) sess)
    , testCase "absolute expires first, idle still valid -> session dies" $ do
        now0 <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Just (addUTCTime 60 now0)   -- 60s
                           , sessionIdleExp = Just (addUTCTime 3600 now0) }   -- 1h
        -- At t+61s: absolute expired, idle valid
        assertBool "expired" (isSessionExpired (addUTCTime 61 now0) sess)
    , testCase "both valid -> session alive" $ do
        now0 <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty
                           , sessionAbsoluteExp = Just (addUTCTime 3600 now0)
                           , sessionIdleExp = Just (addUTCTime 3600 now0) }
        assertBool "not expired" (not (isSessionExpired (addUTCTime 100 now0) sess))
    , testCase "rolling keeps session alive until absolute cap" $ do
        now0 <- getCurrentTime
        sid <- newSessionId
        let absTime = addUTCTime 300 now0  -- 5min absolute
        -- Session with 60s idle, refreshed at each "request"
        let sess0 = Session { sessionId = sid, sessionData = Map.empty
                            , sessionAbsoluteExp = Just absTime
                            , sessionIdleExp = Just (addUTCTime 60 now0) }

        -- Refresh at t+270s: idle rolls to t+330
        let t270 = addUTCTime 270 now0
        let sess1 = refreshIdleExp (Just 60) t270 sess0
        assertBool "alive at 4.5min (after refresh)" (not (isSessionExpired t270 sess1))
        assertEqual "idle rolled to t+330" (Just (addUTCTime 330 now0)) (sessionIdleExp sess1)
        assertEqual "abs unchanged" (Just absTime) (sessionAbsoluteExp sess1)

        -- At t+301s: absolute expired (301 > 300), even though idle = t+330
        let t301 = addUTCTime 301 now0
        assertBool "dead at 5min1s" (isSessionExpired t301 sess1)
    ]
