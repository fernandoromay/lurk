module RequestSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Data.Text qualified as T

import Lurk.Request (parseIpChain)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.Request"
    [ testParseIpChain
    ]

testParseIpChain :: TestTree
testParseIpChain = testGroup "parseIpChain"
    [ testCase "single IP" $
        parseIpChain "1.2.3.4" @?= ["1.2.3.4"]
    , testCase "multiple IPs" $
        parseIpChain "1.2.3.4, 5.6.7.8" @?= ["1.2.3.4", "5.6.7.8"]
    , testCase "multiple IPs with extra whitespace" $
        parseIpChain "1.2.3.4 , 5.6.7.8 , 9.0.1.2" @?= ["1.2.3.4", "5.6.7.8", "9.0.1.2"]
    , testCase "empty string" $
        parseIpChain "" @?= []
    , testCase "comma only" $
        parseIpChain "," @?= []
    , testCase "leading and trailing commas" $
        parseIpChain ",1.2.3.4," @?= ["1.2.3.4"]
    , testCase "IPv6 address" $
        parseIpChain "::1" @?= ["::1"]
    , testCase "mixed IPv4 and IPv6" $
        parseIpChain "192.168.1.1, ::1" @?= ["192.168.1.1", "::1"]
    ]
