module SecuritySpec (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)
import Network.Wai.Test (SResponse(..), runSession, defaultRequest, request)
import Network.Wai (responseLBS)
import Network.HTTP.Types (ok200, HeaderName, ResponseHeaders)
import Data.ByteString qualified as BS

import Lurk.Routes.Security (securityHeaders, securityHeadersWith)

tests :: TestTree
tests = testGroup "Security"
    [ testCase "defaults add common security headers" $ do
        let app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (securityHeaders app)
        let hdrs = simpleHeaders res
        assertBool "has X-Content-Type-Options" $ hasHeader "X-Content-Type-Options" hdrs
        assertBool "has X-Frame-Options" $ hasHeader "X-Frame-Options" hdrs
        assertBool "has X-XSS-Protection" $ hasHeader "X-XSS-Protection" hdrs
        assertBool "has Referrer-Policy" $ hasHeader "Referrer-Policy" hdrs
        assertBool "has Permissions-Policy" $ hasHeader "Permissions-Policy" hdrs

    , testCase "securityHeadersWith can add new headers" $ do
        let extra = [("X-Custom", "test-value")]
            app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (securityHeadersWith extra app)
        let hdrs = simpleHeaders res
        assertBool "has custom header" $ hasHeader "X-Custom" hdrs
        assertBool "still has defaults" $ hasHeader "X-Content-Type-Options" hdrs

    , testCase "securityHeadersWith can override defaults" $ do
        let extra = [("X-Frame-Options", "SAMEORIGIN")]
            app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (securityHeadersWith extra app)
        let hdrs = simpleHeaders res
        assertBool "has overridden X-Frame-Options" $ hasHeaderValue "X-Frame-Options" "SAMEORIGIN" hdrs

    , testCase "securityHeadersWith removes header on empty value" $ do
        let extra = [("X-XSS-Protection", "")]
            app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (securityHeadersWith extra app)
        let hdrs = simpleHeaders res
        assertBool "X-XSS-Protection removed" $ not (hasHeader "X-XSS-Protection" hdrs)

    , testCase "securityHeadersWith empty value removes non-default" $ do
        let extra = [("X-Content-Type-Options", ""), ("X-New-Header", "added")]
            app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (securityHeadersWith extra app)
        let hdrs = simpleHeaders res
        assertBool "X-Content-Type-Options removed" $ not (hasHeader "X-Content-Type-Options" hdrs)
        assertBool "has new header" $ hasHeader "X-New-Header" hdrs

    , testCase "response status 200 with headers" $ do
        let app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (securityHeaders app)
        assertEqual "status is 200" ok200 (simpleStatus res)

    , testCase "multiple overrides" $ do
        let extra =
                [ ("X-Frame-Options", "SAMEORIGIN")
                , ("Referrer-Policy", "no-referrer")
                , ("X-Extra", "yes")
                ]
            app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (securityHeadersWith extra app)
        let hdrs = simpleHeaders res
        assertBool "X-Frame-Options overridden" $ hasHeaderValue "X-Frame-Options" "SAMEORIGIN" hdrs
        assertBool "Referrer-Policy overridden" $ hasHeaderValue "Referrer-Policy" "no-referrer" hdrs
        assertBool "has extra header" $ hasHeader "X-Extra" hdrs
        assertBool "still has X-Content-Type-Options" $ hasHeader "X-Content-Type-Options" hdrs
    ]

-- Helpers

hasHeader :: HeaderName -> ResponseHeaders -> Bool
hasHeader name = any (\(k, _) -> k == name)

hasHeaderValue :: HeaderName -> BS.ByteString -> ResponseHeaders -> Bool
hasHeaderValue name val = any (\(k, v) -> k == name && v == val)
