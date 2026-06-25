module Lurk.Routes
    ( currentPath
    , isSubpath
    , trailingSlash
    , redirect
    ) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Lazy qualified as TL
import Network.HTTP.Types (status301)
import Network.Wai (rawPathInfo, rawQueryString, responseBuilder)
import Network.Wai qualified as Wai
import Lurk.Core (Action)
import qualified Lurk.Core
import Lurk.Request (request)

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
