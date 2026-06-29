{-# LANGUAGE RankNTypes #-}
module Lurk.Prelude
    ( module Prelude
    , module Lurk.SEO
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
    , clientIp
    , ipChain
    , getCookie
    , setCookie
    , setSimpleCookie
    , deleteCookie
    , notFound
    , serverError
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
    , ViewContext(..)
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
    , csrfToken
    -- Flash
    , FlashLevel(..)
    , Flash(..)
    , flash
    , setFlash
    , flashSuccess
    , flashError
    , flashWarning
    -- Env
    , loadEnv
    , loadEnvFile
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Map (Map)
import Data.Text (Text)
import Lurk.Assets (asset, mkAssetPath)
import Lurk.Html (Html, ToHtml (..), renderHtml, forEach, forEachWithIndex)
import Lurk.QQ (lurk)
import Lurk.Routes (isSubpath, trailingSlash, redirect, RouteOption(..), routeSettings, get, post, delete, put, patch, getSubset, postSubset, deleteSubset, putSubset, patchSubset, getSingle, postSingle, deleteSingle, putSingle, patchSingle)
import Lurk.Request (preferredLanguages, fetchCurrentPath, clientIp, ipChain)
import Lurk.Cookie (getCookie, setCookie, setSimpleCookie, deleteCookie)
import Lurk.Session (SessionId, Session, sessionId, getSession, getSessionValue, setSessionValue, deleteSessionValue, destroySession)
import Lurk.Flash (FlashLevel(..), Flash(..), setFlash, getFlash, flashSuccess, flashError, flashWarning)
import Lurk.Env (loadEnv, loadEnvFile, getEnv, getEnvInt, getEnvBool, getEnvWithDefault, requireEnv, hasEnv)
import Lurk.View (ViewContext(..), ViewCtx, render, currentPath, csrfToken, flash)
import Lurk.SEO
import Lurk.App (LurkApp)
import Lurk.Language (withLang)
import Lurk.Core (Action, html, queryParam)
import Lurk.Core qualified
import Network.HTTP.Types qualified as Http
import Prelude

-- | Catch-all route that automatically sets the HTTP 404 status
notFound :: Action () -> LurkApp
notFound action = Lurk.Core.notFound (Lurk.Core.status Http.status404 >> action)

-- | Catch-all route that automatically sets the HTTP 500 status
serverError :: Action () -> LurkApp
serverError action = Lurk.Core.notFound (Lurk.Core.status Http.status500 >> action)
