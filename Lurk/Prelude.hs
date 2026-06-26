{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ImplicitParams #-}
module Lurk.Prelude
    ( module Prelude
    , Text
    , Map
    , liftIO
    , Action
    , queryParam
    , html
    , redirect
    , lurk
    , renderHtml
    , forEach
    , forEachWithIndex
    , render
    , Html
    , ToHtml (..)
    , asset
    , mkAssetPath
    , currentPath
    , isSubpath
    , trailingSlash
    , preferredLanguages
    , resolveLanguage
    , clientIp
    , ipChain
    , contextValue
    , getCookie
    , setCookie
    , setSimpleCookie
    , deleteCookie
    , notFound
    , serverError
    , module Lurk.SEO
    , routeSettings
    , get
    , post
    , delete
    , put
    , patch
    , getSubset
    , postSubset
    , deleteSubset
    , putSubset
    , patchSubset
    , getSingle
    , postSingle
    , deleteSingle
    , putSingle
    , patchSingle
    , RouteOption (..)
    -- Language
    , withLang
    , ViewCtx
    -- Env
    , getEnv
    , getEnvInt
    , getEnvBool
    , getEnvWithDefault
    , requireEnv
    , hasEnv
    -- Session
    , SessionId
    , Session
    , sessionId
    , getSession
    , getSessionValue
    , setSessionValue
    , deleteSessionValue
    , destroySession
    -- CSRF
    , CsrfToken
    -- Flash
    , FlashLevel(..)
    , Flash(..)
    , setFlash
    , getFlash
    , flashSuccess
    , flashError
    , flashWarning
    , renderFlash
    , renderFlashMaybe
    -- Env
    , loadEnv
    , loadEnvFile
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Map (Map)
import Data.Text (Text)
import Data.Text.Lazy qualified as TL
import Lurk.Assets (asset, mkAssetPath)
import Lurk.Html (Html, ToHtml (..), renderHtml, forEach, forEachWithIndex)
import Lurk.QQ (lurk)
import Lurk.Routes (isSubpath, currentPath, trailingSlash, redirect, RouteOption(..), routeSettings, get, post, delete, put, patch, getSubset, postSubset, deleteSubset, putSubset, patchSubset, getSingle, postSingle, deleteSingle, putSingle, patchSingle)
import Lurk.Request (preferredLanguages, resolveLanguage, clientIp, ipChain)
import Lurk.Cookie (getCookie, setCookie, setSimpleCookie, deleteCookie)
import Lurk.Session (SessionId, Session, sessionId, getSession, getSessionValue, setSessionValue, deleteSessionValue, destroySession)
import Lurk.CSRF (CsrfToken, csrfToken)
import Lurk.Flash (FlashLevel(..), Flash(..), setFlash, getFlash, flashSuccess, flashError, flashWarning, renderFlash, renderFlashMaybe)
import Lurk.Env (loadEnv, loadEnvFile, getEnv, getEnvInt, getEnvBool, getEnvWithDefault, requireEnv, hasEnv)
import Lurk.SEO
import Lurk.App (LurkApp)
import Lurk.Language (withLang)
import Lurk.Core (Action, html, queryParam)
import Lurk.Core qualified
import Network.HTTP.Types qualified as Http
import Prelude

-- | View context: implicit parameters available in views and partials.
-- The @lang@ type variable allows projects to use their own language type.
type ViewCtx lang = (?currentPath :: Text, ?params :: [(Text, Text)], ?lang :: lang, ?csrfToken :: Text)

-- | Look up a value in the request context by key
contextValue :: (?params :: [(Text, Text)]) => Text -> Maybe Text
contextValue key = lookup key ?params

-- | Renders LURK Html into a Scotty response
-- Provides @?currentPath@, @?params@, and @?csrfToken@ as implicit parameters.
-- @?lang@ comes from the calling controller's scope (via 'withLang'),
-- not from this function — it flows directly to views.
render :: ((?currentPath :: Text, ?params :: [(Text, Text)], ?csrfToken :: Text) => Html) -> [(Text, Text)] -> Action ()
render viewHtml ctx = do
    uri <- currentPath
    token <- csrfToken
    let ?currentPath = uri
        ?params = ctx
        ?csrfToken = token
    html . TL.fromStrict . renderHtml $ viewHtml

-- | Catch-all route that automatically sets the HTTP 404 status
notFound :: Action () -> LurkApp
notFound action = Lurk.Core.notFound (Lurk.Core.status Http.status404 >> action)

-- | Catch-all route that automatically sets the HTTP 500 status
serverError :: Action () -> LurkApp
serverError action = Lurk.Core.notFound (Lurk.Core.status Http.status500 >> action)
