{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ImplicitParams #-}
module Lurk.Prelude
  ( module Prelude,
    Text,
    Map,
    liftIO,
    ActionM,
    ScottyM,
    scotty,
    get,
    post,
    captureParam,
    queryParam,
    formParam,
    lurk,
    renderHtml,
    renderView,
    Html,
    ToHtml (..),
    asset,
    mkAssetPath,
    getRoute,
    postRoute,
    currentPath,
    activeClass,
    middleware,
    notFound,
    module Lurk.SEO,
  )
where

import Control.Monad.IO.Class (liftIO)
import Data.Map (Map)
import Data.Text (Text)
-- Our own custom HSX engine

import Data.Text.Lazy qualified as TL
import Lurk.Assets (asset, mkAssetPath)
import Lurk.Html (Html, ToHtml (..), renderHtml)
import Lurk.QQ (lurk)
-- Routes Handlers
import Lurk.Routes (activeClass, currentPath, getRoute, postRoute)
import Lurk.SEO
import Web.Scotty (ActionM, ScottyM, captureParam, formParam, get, html, middleware, notFound, post, queryParam, scotty)
import Prelude

-- | Renders LURK Html into a Scotty response
-- Automatically provides the request path into the implicit parameter `?currentPath`
renderView :: ((?currentPath :: Text) => Html) -> ActionM ()
renderView viewHtml = do
    uri <- currentPath
    let ?currentPath = uri
    html . TL.fromStrict . renderHtml $ viewHtml
