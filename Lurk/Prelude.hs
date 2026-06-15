{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ImplicitParams #-}
module Lurk.Prelude
    ( module Prelude
    , Text
    , Map
    , liftIO
    , Action
    , captureParam
    , queryParam
    , formParam
    , lurk
    , renderHtml
    , render
    , Html
    , ToHtml (..)
    , asset
    , mkAssetPath
    , currentPath
    , activeClass
    , trailingSlash
    , preferredLanguages
    , cfCountry
    , resolveLanguage
    , notFound
    , module Lurk.SEO
    -- Lurk.App
    , LurkApp
    , runLurk
    , routeSettings
    , getPage
    , getPages
    , postAction
    , RouteOption (..)
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Map (Map)
import Data.Text (Text)
import Data.Text.Lazy qualified as TL
import Lurk.Assets (asset, mkAssetPath)
import Lurk.Html (Html, ToHtml (..), renderHtml)
import Lurk.QQ (lurk)
import Lurk.Routes (activeClass, currentPath, trailingSlash)
import Lurk.Request (preferredLanguages, cfCountry, resolveLanguage)
import Lurk.SEO
import Lurk.App (LurkApp, Action, getPage, getPages, postAction, routeSettings, runLurk, RouteOption(..))
import Web.Scotty (captureParam, formParam, html, notFound, queryParam)
import Prelude

-- | Renders LURK Html into a Scotty response
-- Automatically provides the request path into the implicit parameter `?currentPath`
render :: ((?currentPath :: Text) => Html) -> Action
render viewHtml = do
    uri <- currentPath
    let ?currentPath = uri
    html . TL.fromStrict . renderHtml $ viewHtml
