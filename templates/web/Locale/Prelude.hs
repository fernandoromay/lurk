module Locale.Prelude
    ( module Data.Map.Strict
    , module GHC.Generics
    , module Lurk.SEO
    , module Paths
    , module Language
    , Text
    , Html
    , lurk
    , assetPath
    ) where

import Data.Map.Strict (Map, fromList)
import Data.Text (Text)
import GHC.Generics (Generic)
import Lurk.Assets (mkAssetPath)
import Lurk.Html (Html)
import Lurk.QQ (lurk)
import Lurk.SEO
import Paths
import Language

mkAssetPath "public"