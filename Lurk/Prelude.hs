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
    , isSubpath
    , trailingSlash
    , preferredLanguages
    , cfCountry
    , resolveLanguage
    , contextValue
    , getCookie
    , setCookie
    , setSimpleCookie
    , deleteCookie
    , notFound
    , module Lurk.SEO
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
import Lurk.Routes (isSubpath, currentPath, trailingSlash)
import Lurk.Request (preferredLanguages, cfCountry, resolveLanguage)
import Lurk.Cookie (getCookie, setCookie, setSimpleCookie, deleteCookie)
import Lurk.SEO
import Lurk.App (LurkApp, Action, getPage, getPages, postAction, routeSettings, runLurk, RouteOption(..))
import Web.Scotty (captureParam, formParam, html, notFound, queryParam)
import Prelude

-- | Look up a value in the request context by key
contextValue :: (?params :: [(Text, Text)]) => Text -> Maybe Text
contextValue key = lookup key ?params

-- | Renders LURK Html into a Scotty response
-- Provides @?currentPath@ and @?params@ as implicit parameters
render :: ((?currentPath :: Text, ?params :: [(Text, Text)]) => Html) -> [(Text, Text)] -> Action ()
render viewHtml ctx = do
    uri <- currentPath
    let ?currentPath = uri
        ?params = ctx
    html . TL.fromStrict . renderHtml $ viewHtml
