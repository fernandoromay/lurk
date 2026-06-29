module FlashSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Concurrent.STM
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time.Clock (addUTCTime, getCurrentTime)

import Lurk.Flash
import Lurk.Session

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.Flash"
    [ testFlashData
    , testFlashSessionIntegration
    ]

testFlashData :: TestTree
testFlashData = testGroup "Flash data type"
    [ testCase "Flash record fields" $ do
        let flash = Flash { flashLevel = FlashSuccess, flashMessage = "Saved!" }
        assertEqual "level" FlashSuccess (flashLevel flash)
        assertEqual "message" "Saved!" (flashMessage flash)
    , testCase "Flash Eq instance" $ do
        let f1 = Flash FlashSuccess "msg"
            f2 = Flash FlashSuccess "msg"
            f3 = Flash FlashError "msg"
        assertEqual "equal flashes" f1 f2
        assertBool "different flashes" (f1 /= f3)
    , testCase "Flash Show instance" $ do
        let flash = Flash FlashError "fail"
        assertBool "show contains level" ("FlashError" `T.isInfixOf` T.pack (show flash))
        assertBool "show contains message" ("fail" `T.isInfixOf` T.pack (show flash))
    ]

testFlashSessionIntegration :: TestTree
testFlashSessionIntegration = testGroup "flash session integration"
    [ testCase "set then read flash keys from session" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        -- Simulate setFlash: write both keys
        atomically $ modifyTVar' (storeSessions store) $ \m ->
            case Map.lookup sid m of
                Nothing -> m
                Just s  ->
                    let sd = Map.insert "flash_level" "error" (Map.insert "flash_message" "Something went wrong" (sessionData s))
                    in Map.insert sid (s { sessionData = sd }) m
        -- Simulate getFlash: read both
        sess' <- readTVarIO (storeSessions store)
        let Just s = Map.lookup sid sess'
            mLvl = getSessionValue "flash_level" s
            mMsg = getSessionValue "flash_message" s
        assertEqual "level" (Just "error") mLvl
        assertEqual "message" (Just "Something went wrong") mMsg
        -- Simulate getFlash consumption: delete both
        atomically $ modifyTVar' (storeSessions store) $ \m ->
            case Map.lookup sid m of
                Nothing -> m
                Just s  ->
                    let sd = Map.delete "flash_level" (Map.delete "flash_message" (sessionData s))
                    in Map.insert sid (s { sessionData = sd }) m
        -- Verify cleared
        sess'' <- readTVarIO (storeSessions store)
        let Just s' = Map.lookup sid sess''
        assertEqual "level cleared" Nothing (getSessionValue "flash_level" s')
        assertEqual "message cleared" Nothing (getSessionValue "flash_message" s')
    , testCase "no flash keys returns Nothing (simulated)" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.empty, sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        sess' <- readTVarIO (storeSessions store)
        let Just s = Map.lookup sid sess'
        assertEqual "no level" Nothing (getSessionValue "flash_level" s)
        assertEqual "no message" Nothing (getSessionValue "flash_message" s)
    , testCase "partial flash keys are ignored" $ do
        store <- newSessionStore Nothing Nothing
        sid <- newSessionId
        now <- getCurrentTime
        let sess = Session { sessionId = sid, sessionData = Map.singleton "flash_level" "success", sessionAbsoluteExp = Just (addUTCTime 3600 now), sessionIdleExp = Nothing }
        atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
        sess' <- readTVarIO (storeSessions store)
        let Just s = Map.lookup sid sess'
            mLvl = getSessionValue "flash_level" s >>= (\t -> if t == "success" then Just "success" else Nothing)
            mMsg = getSessionValue "flash_message" s
        -- Only level set, no message -> getFlash would return Nothing
        assertBool "has level" (mLvl == Just "success")
        assertEqual "no message" Nothing mMsg
    ]
