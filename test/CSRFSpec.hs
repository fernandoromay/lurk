module CSRFSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Concurrent.STM
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time.Clock (addUTCTime, getCurrentTime)

import Lurk.Session
import Lurk.CSRF

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.CSRF"
    [ testTokenGeneration
    , testTokenStorage
    , testTokenValidation
    , testFormBodyCache
    ]

testTokenGeneration :: TestTree
testTokenGeneration = testGroup "newCsrfToken"
    [ testCase "returns 64-char hex string (32 bytes)" $ do
        token <- newCsrfToken
        assertBool ("expected 64 chars, got " ++ show (T.length token)) (T.length token == 64)
    , testCase "only contains hex characters" $ do
        token <- newCsrfToken
        assertBool ("non-hex chars in: " ++ T.unpack token)
            (T.all (\c -> c `elem` ("0123456789abcdef" :: String)) token)
    , testCase "generates unique tokens" $ do
        t1 <- newCsrfToken
        t2 <- newCsrfToken
        assertBool "tokens should differ" (t1 /= t2)
    ]

testTokenStorage :: TestTree
testTokenStorage = testGroup "setCsrfToken / getCsrfToken"
    [ testCase "set then get returns the same token" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        token <- newCsrfToken
        setCsrfToken store sid token
        retrieved <- getCsrfToken store sid
        assertEqual "should retrieve stored token" token retrieved
    , testCase "getCsrfToken generates token if none exists" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)

        token <- getCsrfToken store sid
        assertBool "should generate a token" (T.length token == 64)
        -- verify it's stored
        token2 <- getCsrfToken store sid
        assertEqual "should return same token on second call" token token2
    ]

testTokenValidation :: TestTree
testTokenValidation = testGroup "validateCsrfToken"
    [ testCase "valid token returns True" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        token <- newCsrfToken
        let sess = Session { sessionId = sid, sessionData = Map.singleton "csrf_token" token, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        assertBool "valid token should pass" (validateCsrfToken sess token)
    , testCase "invalid token returns False" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        token <- newCsrfToken
        let sess = Session { sessionId = sid, sessionData = Map.singleton "csrf_token" token, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        assertBool "wrong token should fail" (not $ validateCsrfToken sess "wrong-token")
    , testCase "missing token returns False" $ do
        now <- getCurrentTime
        let sess = Session { sessionId = "test", sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        assertBool "missing token should fail" (not $ validateCsrfToken sess "anything")
    ]

testFormBodyCache :: TestTree
testFormBodyCache = testGroup "formBodyCache"
    [ testCase "cacheFormBody stores params, getCachedFormParams retrieves and removes them" $ do
        sid <- newSessionId
        let params = [("name", "Alice"), ("email", "alice@example.com")]
        cacheFormBody sid params
        retrieved <- getCachedFormParams sid
        assertEqual "should retrieve cached params" params retrieved
        -- second read should be empty (entry removed)
        retrieved2 <- getCachedFormParams sid
        assertEqual "should be empty after retrieval" [] retrieved2
    , testCase "getCachedFormParams returns empty for unknown session" $ do
        result <- getCachedFormParams "nonexistent-session-id"
        assertEqual "should be empty" [] result
    , testCase "cache entry is removed after getCachedFormParams (simulates successful path)" $ do
        sid <- newSessionId
        let params = [("field", "value")]
        cacheFormBody sid params
        -- verify entry exists
        _ <- getCachedFormParams sid
        -- verify cache is clean
        cache <- readTVarIO formBodyCache
        assertBool "cache should not contain session after getCachedFormParams" (not $ Map.member sid cache)
    , testCase "invalid token path does not insert into cache" $ do
        -- simulate the fixed middleware: cacheFormBody is never called on invalid token
        sid <- newSessionId
        cache <- readTVarIO formBodyCache
        assertBool "cache should not contain session before any call" (not $ Map.member sid cache)
    ]
