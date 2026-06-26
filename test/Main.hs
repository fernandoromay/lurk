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
    ]
