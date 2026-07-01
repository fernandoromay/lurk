module Main (main) where

import Test.Tasty

import qualified SessionSpec
import qualified CSRFSpec
import qualified SMTPSpec
import qualified FlashSpec
import qualified RequestSpec
import qualified QQSpec
import qualified LogSpec
import qualified SecuritySpec
import qualified ErrorSpec
import qualified LanguageSpec
import qualified ValidateSpec
import qualified DBSpec

main :: IO ()
main = defaultMain $ testGroup "lurk"
    [ SessionSpec.tests
    , CSRFSpec.tests
    , SMTPSpec.tests
    , FlashSpec.tests
    , RequestSpec.tests
    , QQSpec.tests
    , LogSpec.tests
    , SecuritySpec.tests
    , ErrorSpec.tests
    , LanguageSpec.tests
    , ValidateSpec.tests
    , DBSpec.tests
    ]
