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
    , cfCountry
    , resolveLanguage
    , clientIp
    , ipChain
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
    , postActions
    , RouteOption (..)
    , getStore
    , getAppEnv
    -- Env
    , Env
    , getEnv
    , getEnvInt
    , getEnvBool
    , getEnvWithDefault
    , requireEnv
    , hasEnv
    -- Session
    , SessionId
    , Session(..)
    , SessionStore(..)
    , newSessionStore
    , getSession
    , getSessionValue
    , setSessionValue
    , deleteSessionValue
    , destroySession
    , newSessionId
    , cleanupSessions
    , readSessionMaxAge
    -- CSRF
    , CsrfToken
    , newCsrfToken
    , getCsrfToken
    , validateCsrfToken
    , getSessionIdFromHeaders
    , cacheFormBody
    , lookupCachedFormParam
    , getCachedFormParams
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
import Lurk.Routes (isSubpath, currentPath, trailingSlash, redirect)
import Lurk.Request (preferredLanguages, cfCountry, resolveLanguage, clientIp, ipChain)
import Lurk.Cookie (getCookie, setCookie, setSimpleCookie, deleteCookie)
import Lurk.Session (SessionId, Session(..), SessionStore, newSessionStore, getSession, getSessionValue, setSessionValue, deleteSessionValue, destroySession, newSessionId, cleanupSessions, readSessionMaxAge)
import Lurk.CSRF (CsrfToken, newCsrfToken, getCsrfToken, validateCsrfToken, getSessionIdFromHeaders, cacheFormBody, lookupCachedFormParam, getCachedFormParams)
import Lurk.Flash (FlashLevel(..), Flash(..), setFlash, getFlash, flashSuccess, flashError, flashWarning, renderFlash, renderFlashMaybe)
import Lurk.Env (Env, loadEnv, loadEnvFile, getEnv, getEnvInt, getEnvBool, getEnvWithDefault, requireEnv, hasEnv)
import Lurk.SEO
import Lurk.App (LurkApp, Action, getPage, getPages, postAction, postActions, routeSettings, runLurk, RouteOption(..), getStore, getAppEnv)
import Web.Scotty (html, queryParam)
import Web.Scotty qualified as Scotty
import Network.HTTP.Types qualified as Http
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

-- | Catch-all route that automatically sets the HTTP 404 status
notFound :: Action () -> LurkApp
notFound action = Scotty.notFound (Scotty.status Http.status404 >> action)
