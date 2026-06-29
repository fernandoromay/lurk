{-# LANGUAGE LambdaCase #-}
module ValidateSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Data.Text (Text)
import Data.Text qualified as T

import Lurk.Form (FormData(..))
import Lurk.Validate

tests :: TestTree
tests = testGroup "Lurk.Validate"
    [ testValidationType
    , testField
    , testRequired
    , testIsEmail
    , testMinLength
    , testMaxLength
    , testNumeric
    , testOneOf
    , testAtLeast
    , testAtMost
    , testCustom
    , testMatches
    , testComposition
    , testRunRules
    , testFieldMaybe
    , testIOValidators
    ]

----------------------------------------------------------------------
-- Validation type
----------------------------------------------------------------------

testValidationType :: TestTree
testValidationType = testGroup "Validation type"
    [ testCase "Success is Semigroup" $ do
        let s1 = Success "a" :: Validation [Text] String
            s2 = Success "b"
        assertEqual "success <> success" (Success "a") (s1 <> s2)
    , testCase "Failure accumulates errors" $ do
        let f1 = Failure ["err1"] :: Validation [String] String
            f2 = Failure ["err2"]
        assertEqual "failure <> failure" (Failure ["err1", "err2"]) (f1 <> f2)
    , testCase "Failure wins over Success" $ do
        let f = Failure ["err"] :: Validation [String] String
            s = Success "ok"
        assertEqual "failure <> success" (Failure ["err"]) (f <> s)
        assertEqual "success <> failure" (Failure ["err"]) (s <> f)
    , testCase "Applicative pure" $ do
        let s = pure "x" :: Validation [String] String
        assertEqual "pure" (Success "x") s
    , testCase "Applicative <*> accumulates" $ do
        let f = Failure ["e1"] :: Validation [String] (String -> String)
            v = Failure ["e2"]
        assertEqual "failure <*> failure" (Failure ["e1", "e2"]) (f <*> v)
    , testCase "Functor fmap" $ do
        let s = Success (1 :: Int) :: Validation [String] Int
        assertEqual "fmap (+1)" (Success 2) ((+1) <$> s)
    ]

----------------------------------------------------------------------
-- field combinator
----------------------------------------------------------------------

testField :: TestTree
testField = testGroup "field"
    [ testCase "extracts field value" $ do
        let fd = FormData [("name", "Alice")]
            rules = field "name" (required "required")
            result = rules fd
        assertEqual "should succeed" (Success (ValidationError "" "")) result
    , testCase "empty field fails required" $ do
        let fd = FormData [("name", "")]
            rules = field "name" (required "required")
            result = rules fd
        case result of
            Failure errs -> do
                assertEqual "1 error" 1 (length errs)
                assertEqual "field name" "name" (vErrorField (head errs))
                assertEqual "message" "required" (vErrorMessage (head errs))
            _ -> assertFailure "should fail"
    , testCase "missing field fails required" $ do
        let fd = FormData [("other", "value")]
            rules = field "name" (required "required")
            result = rules fd
        case result of
            Failure errs -> assertEqual "1 error" 1 (length errs)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- required
----------------------------------------------------------------------

testRequired :: TestTree
testRequired = testGroup "required"
    [ testCase "non-empty value succeeds" $ do
        let fd = FormData [("email", "test@example.com")]
            result = field "email" (required "required") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "empty value fails" $ do
        let fd = FormData [("email", "")]
            result = field "email" (required "required") fd
        case result of
            Failure [e] -> assertEqual "msg" "required" (vErrorMessage e)
            _ -> assertFailure "should fail with 1 error"
    ]

----------------------------------------------------------------------
-- isEmail
----------------------------------------------------------------------

testIsEmail :: TestTree
testIsEmail = testGroup "isEmail"
    [ testCase "valid email succeeds" $ do
        let fd = FormData [("email", "user@domain.com")]
            result = field "email" (isEmail "invalid") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "missing @ fails" $ do
        let fd = FormData [("email", "userdomain.com")]
            result = field "email" (isEmail "invalid") fd
        case result of
            Failure [e] -> assertEqual "msg" "invalid" (vErrorMessage e)
            _ -> assertFailure "should fail"
    , testCase "missing domain fails" $ do
        let fd = FormData [("email", "user@")]
            result = field "email" (isEmail "invalid") fd
        case result of
            Failure [e] -> assertEqual "msg" "invalid" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- minLength
----------------------------------------------------------------------

testMinLength :: TestTree
testMinLength = testGroup "minLength"
    [ testCase "long enough succeeds" $ do
        let fd = FormData [("pw", "hello")]
            result = field "pw" (minLength 3 "too short") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "too short fails" $ do
        let fd = FormData [("pw", "hi")]
            result = field "pw" (minLength 3 "too short") fd
        case result of
            Failure [e] -> assertEqual "msg" "too short" (vErrorMessage e)
            _ -> assertFailure "should fail"
    , testCase "exact length succeeds" $ do
        let fd = FormData [("pw", "abc")]
            result = field "pw" (minLength 3 "too short") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    ]

----------------------------------------------------------------------
-- maxLength
----------------------------------------------------------------------

testMaxLength :: TestTree
testMaxLength = testGroup "maxLength"
    [ testCase "short enough succeeds" $ do
        let fd = FormData [("name", "Al")]
            result = field "name" (maxLength 10 "too long") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "too long fails" $ do
        let fd = FormData [("name", "Alice Bob Charlie")]
            result = field "name" (maxLength 5 "too long") fd
        case result of
            Failure [e] -> assertEqual "msg" "too long" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- numeric
----------------------------------------------------------------------

testNumeric :: TestTree
testNumeric = testGroup "numeric"
    [ testCase "integer succeeds" $ do
        let fd = FormData [("age", "25")]
            result = field "age" (numeric "not a number") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "decimal succeeds" $ do
        let fd = FormData [("price", "19.99")]
            result = field "price" (numeric "not a number") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "text fails" $ do
        let fd = FormData [("age", "abc")]
            result = field "age" (numeric "not a number") fd
        case result of
            Failure [e] -> assertEqual "msg" "not a number" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- oneOf
----------------------------------------------------------------------

testOneOf :: TestTree
testOneOf = testGroup "oneOf"
    [ testCase "valid value succeeds" $ do
        let fd = FormData [("role", "admin")]
            result = field "role" (oneOf ["admin", "editor"] "invalid") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "invalid value fails" $ do
        let fd = FormData [("role", "superadmin")]
            result = field "role" (oneOf ["admin", "editor"] "invalid") fd
        case result of
            Failure [e] -> assertEqual "msg" "invalid" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- atLeast
----------------------------------------------------------------------

testAtLeast :: TestTree
testAtLeast = testGroup "atLeast"
    [ testCase "above bound succeeds" $ do
        let fd = FormData [("age", "20")]
            result = field "age" (atLeast (18 :: Int) "too low") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "at bound succeeds" $ do
        let fd = FormData [("age", "18")]
            result = field "age" (atLeast (18 :: Int) "too low") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "below bound fails" $ do
        let fd = FormData [("age", "15")]
            result = field "age" (atLeast (18 :: Int) "too low") fd
        case result of
            Failure [e] -> assertEqual "msg" "too low" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- atMost
----------------------------------------------------------------------

testAtMost :: TestTree
testAtMost = testGroup "atMost"
    [ testCase "below bound succeeds" $ do
        let fd = FormData [("qty", "5")]
            result = field "qty" (atMost (10 :: Int) "too high") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "at bound succeeds" $ do
        let fd = FormData [("qty", "10")]
            result = field "qty" (atMost (10 :: Int) "too high") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "above bound fails" $ do
        let fd = FormData [("qty", "15")]
            result = field "qty" (atMost (10 :: Int) "too high") fd
        case result of
            Failure [e] -> assertEqual "msg" "too high" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- custom
----------------------------------------------------------------------

testCustom :: TestTree
testCustom = testGroup "custom"
    [ testCase "passing predicate succeeds" $ do
        let fd = FormData [("url", "https://example.com")]
            result = field "url" (custom (\v -> "https://" `T.isPrefixOf` v) "must be https") fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "failing predicate fails" $ do
        let fd = FormData [("url", "http://example.com")]
            result = field "url" (custom (\v -> "https://" `T.isPrefixOf` v) "must be https") fd
        case result of
            Failure [e] -> assertEqual "msg" "must be https" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- matches
----------------------------------------------------------------------

testMatches :: TestTree
testMatches = testGroup "matches"
    [ testCase "equal values succeed" $ do
        let fd = FormData [("pw", "secret"), ("confirm", "secret")]
            result = matches "pw" "confirm" "no match" fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "different values fail" $ do
        let fd = FormData [("pw", "secret"), ("confirm", "other")]
            result = matches "pw" "confirm" "no match" fd
        case result of
            Failure [e] -> do
                assertEqual "field" "pw" (vErrorField e)
                assertEqual "msg" "no match" (vErrorMessage e)
            _ -> assertFailure "should fail"
    , testCase "missing field fails" $ do
        let fd = FormData [("pw", "secret")]
            result = matches "pw" "confirm" "no match" fd
        case result of
            Failure [e] -> assertEqual "msg" "no match" (vErrorMessage e)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- Composition (<>)
----------------------------------------------------------------------

testComposition :: TestTree
testComposition = testGroup "composition with <>"
    [ testCase "all pass -> success" $ do
        let fd = FormData [("name", "Alice"), ("email", "a@b.com")]
            rules = field "name" (required "name required")
                 <> field "email" (required "email required" <> isEmail "email invalid")
            result = rules fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "one field fails -> failure with errors" $ do
        let fd = FormData [("name", ""), ("email", "a@b.com")]
            rules = field "name" (required "name required")
                 <> field "email" (required "email required" <> isEmail "email invalid")
            result = rules fd
        case result of
            Failure errs -> assertEqual "1 error" 1 (length errs)
            _ -> assertFailure "should fail"
    , testCase "multiple validators on same field accumulate" $ do
        let fd = FormData [("email", "")]
            rules = field "email" (required "email required" <> isEmail "email invalid")
            result = rules fd
        case result of
            Failure errs -> assertEqual "2 errors" 2 (length errs)
            _ -> assertFailure "should fail"
    , testCase "three fields all fail" $ do
        let fd = FormData [("", ""), ("", ""), ("", "")]
            rules = field "a" (required "a req")
                 <> field "b" (required "b req")
                 <> field "c" (required "c req")
            result = rules fd
        case result of
            Failure errs -> assertEqual "3 errors" 3 (length errs)
            _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- runRules
----------------------------------------------------------------------

testRunRules :: TestTree
testRunRules = testGroup "runRules"
    [ testCase "success returns FormData" $ do
        let fd = FormData [("name", "Alice")]
            rules = field "name" (required "required")
            result = runRules rules fd
        case result of
            Success fd' -> assertEqual "same fd" (rawParams fd) (rawParams fd')
            Failure _ -> assertFailure "should succeed"
    , testCase "failure returns errors" $ do
        let fd = FormData [("name", "")]
            rules = field "name" (required "required")
            result = runRules rules fd
        case result of
            Failure errs -> assertEqual "1 error" 1 (length errs)
            Success _ -> assertFailure "should fail"
    ]

----------------------------------------------------------------------
-- fieldMaybe
----------------------------------------------------------------------

testFieldMaybe :: TestTree
testFieldMaybe = testGroup "fieldMaybe"
    [ testCase "missing field passes" $ do
        let fd = FormData []
            rules = fieldMaybe "opt" (\_ -> Success (ValidationError "" ""))
            result = rules fd
        assertEqual "success" (Success (ValidationError "" "")) result
    , testCase "present field validated" $ do
        let fd = FormData [("opt", "val")]
            rules = fieldMaybe "opt" $ \case
                Just _  -> Success (ValidationError "" "")
                Nothing -> Failure [ValidationError "opt" "unexpected"]
            result = rules fd
        assertEqual "success" (Success (ValidationError "" "")) result
    ]

----------------------------------------------------------------------
-- IO validators
----------------------------------------------------------------------

testIOValidators :: TestTree
testIOValidators = testGroup "IO validators"
    [ testCase "noIO always passes" $ do
        result <- noIO ("test" :: String)
        assertEqual "right" (Right "test") result
    , testCase "liftPred passing" $ do
        result <- liftPred (> 5) "too small" (10 :: Int)
        assertEqual "right" (Right 10) result
    , testCase "liftPred failing" $ do
        result <- liftPred (> 5) "too small" (3 :: Int)
        assertEqual "left" (Left "too small") result
    , testCase "composition short-circuits" $ do
        let v1 = liftPred (> 0) "non-positive"
            v2 = liftPred (< 10) "too large"
            composed = v1 <.?> v2
        result <- composed (5 :: Int)
        assertEqual "right" (Right 5) result
    , testCase "composition fails first" $ do
        let v1 = liftPred (> 0) "non-positive"
            v2 = liftPred (< 10) "too large"
            composed = v1 <.?> v2
        result <- composed (-1 :: Int)
        assertEqual "left" (Left "non-positive") result
    , testCase "composition fails second" $ do
        let v1 = liftPred (> 0) "non-positive"
            v2 = liftPred (< 10) "too large"
            composed = v1 <.?> v2
        result <- composed (15 :: Int)
        assertEqual "left" (Left "too large") result
    ]
