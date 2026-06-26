module LanguageSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Data.Text qualified as T
import Data.Data (Data)

import Lurk.Language.Detect

data TestLang = EN | ES | KO
    deriving (Eq, Enum, Bounded, Data, Show)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Lurk.Language.Detect"
    [ testParseAcceptLanguage
    , testMatchLanguage
    , testLangFromCookie
    , testCountryLang
    ]

testParseAcceptLanguage :: TestTree
testParseAcceptLanguage = testGroup "parseAcceptLanguage"
    [ testCase "single language" $
        parseAcceptLanguage "es" @?= [("es", 1.0)]
    , testCase "multiple languages without q" $
        parseAcceptLanguage "es, en, ko" @?=
            [("es", 1.0), ("en", 1.0), ("ko", 1.0)]
    , testCase "languages with quality values" $
        parseAcceptLanguage "es, en-US;q=0.9, ko;q=0.5" @?=
            [("es", 1.0), ("en-US", 0.9), ("ko", 0.5)]
    , testCase "sorts by quality descending" $
        parseAcceptLanguage "ko;q=0.5, es;q=1.0, en;q=0.8" @?=
            [("es", 1.0), ("en", 0.8), ("ko", 0.5)]
    , testCase "handles whitespace" $
        parseAcceptLanguage "  es , en-US;q=0.9  " @?=
            [("es", 1.0), ("en-US", 0.9)]
    , testCase "empty string" $
        parseAcceptLanguage "" @?= []
    , testCase "clamps quality to [0, 1]" $
        parseAcceptLanguage "es;q=1.5" @?= [("es", 1.0)]
    , testCase "clamps quality to [0, 1]" $
        parseAcceptLanguage "es;q=-0.5" @?= [("es", 0.0)]
    , testCase "malformed q value defaults to 1.0" $
        parseAcceptLanguage "es;q=abc" @?= [("es", 1.0)]
    , testCase "language with subtag" $
        parseAcceptLanguage "en-US" @?= [("en-US", 1.0)]
    ]

testMatchLanguage :: TestTree
testMatchLanguage = testGroup "matchLanguage"
    [ testCase "exact match" $
        matchLanguage ["en", "es", "ko"] [("es", 1.0)] @?= Just "es"
    , testCase "subtag match (en-US matches en)" $
        matchLanguage ["en", "es"] [("en-US", 0.9), ("es", 1.0)] @?= Just "en"
    , testCase "no match" $
        matchLanguage ["en", "es"] [("fr", 1.0)] @?= Nothing
    , testCase "empty prefs" $
        matchLanguage ["en", "es"] [] @?= Nothing
    , testCase "empty supported" $
        matchLanguage [] [("en", 1.0)] @?= Nothing
    , testCase "takes first match from sorted prefs" $
        matchLanguage ["en", "es"] [("es", 0.9), ("en", 1.0)] @?= Just "es"
    , testCase "ko subtag matches ko" $
        matchLanguage ["en", "ko"] [("ko-KR", 1.0)] @?= Just "ko"
    ]

testLangFromCookie :: TestTree
testLangFromCookie = testGroup "langFromCookie"
    [ testCase "valid language" $
        langFromCookie EN "es" @?= Just ES
    , testCase "default language" $
        langFromCookie EN "en" @?= Just EN
    , testCase "invalid language" $
        langFromCookie EN "fr" @?= Nothing
    , testCase "handles uppercase" $
        langFromCookie EN "ES" @?= Just ES
    , testCase "handles dash" $
        langFromCookie EN "en-US" @?= Nothing
    ]

testCountryLang :: TestTree
testCountryLang = testGroup "countryLang"
    [ testCase "matches country" $
        countryLang [EN, ES, KO] [("ES", ES), ("KR", KO)] "ES" @?= ES
    , testCase "falls back to first available" $
        countryLang [EN, ES, KO] [("ES", ES), ("KR", KO)] "US" @?= EN
    , testCase "empty mapping returns default" $
        countryLang [EN, ES] [] "ES" @?= EN
    ]
