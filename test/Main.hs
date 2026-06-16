module Main (main) where

import Test.Tasty

import qualified SessionSpec
import qualified CSRFSpec

main :: IO ()
main = defaultMain $ testGroup "lurk"
    [ SessionSpec.tests
    , CSRFSpec.tests
    ]
