module View.Prelude
    ( module Lurk.Prelude
    , module Language
    , assetPath
    , render
    ) where

import Lurk.Prelude hiding (render)
import Lurk.Prelude qualified as Lurk
import Language

mkAssetPath "public"
