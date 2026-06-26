module Lurk.Routes
    ( currentPath
    , isSubpath
    , trailingSlash
    , RouteOption(..)
    , routeSettings
    -- All languages
    , get
    , post
    , delete
    , put
    , patch
    -- Subset of languages
    , getSubset
    , postSubset
    , deleteSubset
    , putSubset
    , patchSubset
    -- Single route (no language)
    , getSingle
    , postSingle
    , deleteSingle
    , putSingle
    , patchSingle
    , redirect
    ) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Lazy qualified as TL
import Network.HTTP.Types (status301, Header)
import Network.Wai (rawPathInfo, rawQueryString, responseBuilder)
import Network.Wai qualified as Wai
import Network.Wai.Middleware.Static (staticPolicy, addBase)
import Network.Wai.Middleware.ForceSSL (forceSSL)
import System.Environment (lookupEnv)
import Lurk.Core (Action)
import qualified Lurk.Core
import Lurk.Routes.Security (securityHeaders, securityHeadersWith)
import Lurk.Request (request)
import Lurk.App (LurkApp)
import Lurk.Language (allLanguages, withLang)
import Web.Scotty (middleware, literal)
import Web.Scotty qualified as Scotty

-- | Redirect to the given path (strict 'Text').
--   Wraps Scotty's redirect which expects lazy 'Text'.
redirect :: Text -> Action a
redirect = Lurk.Core.redirect . TL.fromStrict

currentPath :: Action T.Text
currentPath = TE.decodeUtf8 . rawPathInfo <$> request

isSubpath :: T.Text -> T.Text -> Bool
isSubpath = T.isPrefixOf

-- Enforce trailing slashes on page routes via 301
-- Paths with a file extension are passed through unchanged
trailingSlash :: Wai.Middleware
trailingSlash app req respond
    | needsSlash = respond $ responseBuilder status301 [("Location", redirectTo)] mempty
    | otherwise = app req respond
  where
    method = Wai.requestMethod req
    rawPath = rawPathInfo req
    lastSeg = BS.takeWhileEnd (/= 47) rawPath -- 47 = '/'
    isAsset = BS.elem 46 lastSeg -- 46 = '.'
    needsSlash =
        method `elem` ["GET", "HEAD"]
        && not isAsset
        && not (BS.null rawPath)
        && BS.last rawPath /= 47
    redirectTo = rawPath <> "/" <> rawQueryString req

data RouteOption
    = TrailingSlashes       -- ^ Enforce trailing slashes
    | ForceSSL              -- ^ Redirect HTTP to HTTPS
    | ServeStatic FilePath  -- ^ Serve a dir of static assets
    | SecurityHeaders       -- ^ Add default security headers (X-Content-Type-Options, X-Frame-Options, etc.)
    | SecurityHeadersWith [Header]  -- ^ Security headers with custom overrides

-- | A smarter ForceSSL that only runs in production
smartForceSSL :: Wai.Middleware
smartForceSSL app req respond = do
    env <- lookupEnv "LURK_ENV"
    if env == Just "production"
        then forceSSL app req respond
        else app req respond

-- Apply a list of route-level settings
routeSettings :: [RouteOption] -> LurkApp
routeSettings = mapM_ apply
  where
    apply TrailingSlashes        = middleware trailingSlash
    apply ForceSSL               = middleware smartForceSSL
    apply (ServeStatic dir)      = middleware $ staticPolicy (addBase dir)
    apply SecurityHeaders        = middleware securityHeaders
    apply (SecurityHeadersWith h) = middleware (securityHeadersWith h)

-- Single route (no language)
getSingle :: Text -> Action () -> LurkApp
getSingle path = Scotty.get (literal $ T.unpack path)

postSingle :: Text -> Action () -> LurkApp
postSingle path = Scotty.post (literal $ T.unpack path)

deleteSingle :: Text -> Action () -> LurkApp
deleteSingle path = Scotty.delete (literal $ T.unpack path)

putSingle :: Text -> Action () -> LurkApp
putSingle path = Scotty.put (literal $ T.unpack path)

patchSingle :: Text -> Action () -> LurkApp
patchSingle path = Scotty.patch (literal $ T.unpack path)

-- Subset of languages
getSubset :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
getSubset langs pathFn actionFn =
    mapM_ (\lang -> getSingle (pathFn lang) (actionFn lang)) langs

postSubset :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
postSubset langs pathFn actionFn =
    mapM_ (\lang -> postSingle (pathFn lang) (actionFn lang)) langs

deleteSubset :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
deleteSubset langs pathFn actionFn =
    mapM_ (\lang -> deleteSingle (pathFn lang) (actionFn lang)) langs

putSubset :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
putSubset langs pathFn actionFn =
    mapM_ (\lang -> putSingle (pathFn lang) (actionFn lang)) langs

patchSubset :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
patchSubset langs pathFn actionFn =
    mapM_ (\lang -> patchSingle (pathFn lang) (actionFn lang)) langs

-- All languages (path function)
get :: (Enum lang, Bounded lang)
    => (lang -> Text) -> ((?lang :: lang) => Action ()) -> LurkApp
get pathFn actionFn = getSubset allLanguages pathFn (`withLang` actionFn)

post :: (Enum lang, Bounded lang)
     => (lang -> Text) -> ((?lang :: lang) => Action ()) -> LurkApp
post pathFn actionFn = postSubset allLanguages pathFn (`withLang` actionFn)

delete :: (Enum lang, Bounded lang)
       => (lang -> Text) -> ((?lang :: lang) => Action ()) -> LurkApp
delete pathFn actionFn = deleteSubset allLanguages pathFn (`withLang` actionFn)

put :: (Enum lang, Bounded lang)
    => (lang -> Text) -> ((?lang :: lang) => Action ()) -> LurkApp
put pathFn actionFn = putSubset allLanguages pathFn (`withLang` actionFn)

patch :: (Enum lang, Bounded lang)
      => (lang -> Text) -> ((?lang :: lang) => Action ()) -> LurkApp
patch pathFn actionFn = patchSubset allLanguages pathFn (`withLang` actionFn)
