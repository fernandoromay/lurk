module SMTPSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Exception (fromException, toException, SomeException)
import Data.Text qualified as T

import Lurk.Email.SMTP

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.Email.SMTP"
    [ testSmtpConfig
    , testEmail
    , testEmailError
    , testSendEmailErrors
    , testSendEmailInsecure
    ]

----------------------------------------------------------------------
-- DATA TYPE TESTS
----------------------------------------------------------------------

testSmtpConfig :: TestTree
testSmtpConfig = testGroup "SmtpConfig"
    [ testCase "Show instance" $ do
        let cfg = mkTestConfig
        assertBool "show contains host" (T.isInfixOf "smtp.test.com" (T.pack (show cfg)))
    , testCase "Eq instance: equal configs" $ do
        let cfg1 = mkTestConfig
            cfg2 = mkTestConfig
        assertEqual "identical configs should be equal" cfg1 cfg2
    , testCase "Eq instance: different configs" $ do
        let cfg1 = mkTestConfig
            cfg2 = cfg1 { smtpHost = "other.com" }
        assertBool "different configs should not be equal" (cfg1 /= cfg2)
    ]

testEmail :: TestTree
testEmail = testGroup "Email"
    [ testCase "Show instance" $ do
        let e = Email "to@test.com" "Subject" "<p>body</p>"
        assertBool "show contains to" (T.isInfixOf "to@test.com" (T.pack (show e)))
    , testCase "Eq instance: equal emails" $ do
        let e1 = Email "a@b.com" "Sub" "Body"
            e2 = Email "a@b.com" "Sub" "Body"
        assertEqual "identical emails should be equal" e1 e2
    , testCase "Eq instance: different emails" $ do
        let e1 = Email "a@b.com" "Sub" "Body"
            e2 = Email "x@b.com" "Sub" "Body"
        assertBool "different emails should not be equal" (e1 /= e2)
    ]

testEmailError :: TestTree
testEmailError = testGroup "EmailError"
    [ testCase "SmtpConnectionError roundtrips through Exception" $ do
        let err = SmtpConnectionError "test"
        assertEqual "fromException should recover" (Just err) (fromException (toException err))
    , testCase "SmtpProtocolError roundtrips through Exception" $ do
        let err = SmtpProtocolError "bad protocol"
        assertEqual "fromException should recover" (Just err) (fromException (toException err))
    , testCase "SmtpAuthError roundtrips through Exception" $ do
        let err = SmtpAuthError "bad creds"
        assertEqual "fromException should recover" (Just err) (fromException (toException err))
    , testCase "SmtpTimeout roundtrips through Exception" $ do
        assertEqual "fromException should recover" (Just SmtpTimeout) (fromException (toException SmtpTimeout))
    , testCase "Show instances" $ do
        assertBool "SmtpConnectionError show" (not (null (show (SmtpConnectionError "x"))))
        assertBool "SmtpProtocolError show" (not (null (show (SmtpProtocolError "x"))))
        assertBool "SmtpAuthError show" (not (null (show (SmtpAuthError "x"))))
        assertBool "SmtpTimeout show" (not (null (show SmtpTimeout)))
    ]

----------------------------------------------------------------------
-- INTEGRATION TESTS (network, fast-fail)
----------------------------------------------------------------------

testSendEmailErrors :: TestTree
testSendEmailErrors = testGroup "sendEmail error handling"
    [ testCase "non-existent host returns SmtpConnectionError or SmtpTimeout" $ do
        let cfg = mkTestConfig { smtpHost = "192.0.2.1" }  -- TEST-NET, unreachable
            email = Email "test@example.com" "Test" "<p>test</p>"
        result <- sendEmail cfg email
        case result of
            Left (SmtpConnectionError _) -> pure ()
            Left SmtpTimeout -> pure ()
            Left other -> assertFailure $ "unexpected error: " ++ show other
            Right () -> assertFailure "should not succeed"
    , testCase "invalid port returns SmtpConnectionError or SmtpTimeout" $ do
        let cfg = mkTestConfig { smtpPort = 1 }
            email = Email "test@example.com" "Test" "<p>test</p>"
        result <- sendEmail cfg email
        case result of
            Left (SmtpConnectionError _) -> pure ()
            Left SmtpTimeout -> pure ()
            Left other -> assertFailure $ "unexpected error: " ++ show other
            Right () -> assertFailure "should not succeed"
    ]

----------------------------------------------------------------------
-- sendEmailInsecure TESTS
----------------------------------------------------------------------

testSendEmailInsecure :: TestTree
testSendEmailInsecure = testGroup "sendEmailInsecure"
    [ testCase "has same type as sendEmail" $ do
        -- Verify sendEmailInsecure exists and compiles with the right type
        let _ = sendEmailInsecure :: SmtpConfig -> Email -> IO (Either EmailError ())
        pure ()
    , testCase "non-existent host returns SmtpConnectionError or SmtpTimeout" $ do
        let cfg = mkTestConfig { smtpHost = "192.0.2.1" }
            email = Email "test@example.com" "Test" "<p>test</p>"
        result <- sendEmailInsecure cfg email
        case result of
            Left (SmtpConnectionError _) -> pure ()
            Left SmtpTimeout -> pure ()
            Left other -> assertFailure $ "unexpected error: " ++ show other
            Right () -> assertFailure "should not succeed"
    ]

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

mkTestConfig :: SmtpConfig
mkTestConfig = SmtpConfig
    { smtpHost       = "smtp.test.com"
    , smtpPort       = 587
    , smtpUsername   = "user@test.com"
    , smtpPassword   = "pass"
    , smtpFrom       = "from@test.com"
    , smtpFromName   = "Test Sender"
    , smtpEncryption = "starttls"
    }
