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
    , captureParam
    , queryParam
    , formParam
    , lurk
    , renderHtml
    , renderView
    , Html
    , ToHtml(..)
    , asset
    , mkAssetPath
    , getRoute
    , postRoute
    , middleware
    , notFound
    , module Lurk.SEO
    ) where

import Prelude
import Data.Text (Text)
import Data.Map (Map)
import Control.Monad.IO.Class (liftIO)
import Web.Scotty (ActionM, ScottyM, scotty, get, post, html, captureParam, queryParam, formParam, middleware, notFound)

-- Our own custom HSX engine
import Lurk.QQ (lurk)
import Lurk.Html (Html, ToHtml(..), renderHtml)
import Lurk.Assets (asset, mkAssetPath)
import Lurk.SEO
import qualified Data.Text.Lazy as TL

-- Routes Handlers
import Lurk.Routes (getRoute, postRoute)

-- | Renders LURK Html into a Scotty response
renderView :: Html -> ActionM ()
renderView = html . TL.fromStrict . renderHtml
