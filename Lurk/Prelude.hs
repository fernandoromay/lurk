module Lurk.Prelude 
    ( module Prelude
    , Text
    , Map
    , liftIO
    , ActionM
    , ScottyM
    , scotty
    , get
    , post
    , html
    , param
    , lurk
    , renderHtml
    , renderView
    , Html
    , ToHtml(..)
    ) where

import Prelude
import Data.Text (Text)
import Data.Map (Map)
import Control.Monad.IO.Class (liftIO)
import Web.Scotty (ActionM, ScottyM, scotty, get, post, html, param)

-- Our own custom HSX engine
import Lurk.QQ (lurk)
import Lurk.Html (Html, ToHtml(..), renderHtml)
import qualified Data.Text.Lazy as TL

-- | Renders LURK Html into a Scotty response
renderView :: Html -> ActionM ()
renderView = html . TL.fromStrict . renderHtml
