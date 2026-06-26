{-# LANGUAGE OverloadedStrings #-}
module ErrorSpec (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)
import Network.Wai.Test (SResponse(..), runSession, request, defaultRequest)
import Network.Wai (responseLBS)
import Network.HTTP.Types (ok200, status500)
import Data.ByteString.Lazy qualified as LB
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

import Lurk.Error (error404View, error500View, errorMiddleware)
import Lurk.Html (renderHtml)

tests :: TestTree
tests = testGroup "Error"
    [ testCase "error404View renders valid HTML with 404" $ do
        let html = renderHtml error404View
        assertBool "contains 404" $ "404" `T.isInfixOf` html
        assertBool "contains Not Found" $ "Not Found" `T.isInfixOf` html
        assertBool "contains Back to Home" $ "Back to Home" `T.isInfixOf` html

    , testCase "error500View renders valid HTML with 500" $ do
        let html = renderHtml error500View
        assertBool "contains 500" $ "500" `T.isInfixOf` html
        assertBool "contains Server Error" $ "Server Error" `T.isInfixOf` html
        assertBool "contains Something went wrong" $ "Something went wrong" `T.isInfixOf` html

    , testCase "errorMiddleware returns 500 on exception" $ do
        let crashingApp _ respond = error "boom"
        res <- runSession (request defaultRequest) (errorMiddleware crashingApp)
        assertEqual "status is 500" status500 (simpleStatus res)
        let body = TE.decodeUtf8 $ LB.toStrict $ simpleBody res
        assertBool "body contains 500" $ "500" `T.isInfixOf` body

    , testCase "errorMiddleware passes normal requests" $ do
        let app req respond = respond $ responseLBS ok200 [] "ok"
        res <- runSession (request defaultRequest) (errorMiddleware app)
        assertEqual "status is 200" ok200 (simpleStatus res)
    ]
