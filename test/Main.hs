module Main (main) where

import Test.Tasty

import qualified SessionSpec
import qualified CSRFSpec
import qualified SMTPSpec
import qualified FlashSpec
import qualified RequestSpec

main :: IO ()
main = defaultMain $ testGroup "lurk"
    [ SessionSpec.tests
    , CSRFSpec.tests
    , SMTPSpec.tests
    , FlashSpec.tests
    , RequestSpec.tests
    ]
