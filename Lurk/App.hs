module Lurk.App
    ( LurkApp
    , Action
    , RouteOption(..)
    , routeSettings
    , runLurk
    , getPage
    , getPages
    , postAction
    ) where

import Data.Text (Text)
import qualified Data.Text as T
import Lurk.Routes (trailingSlash)
import Network.Wai.Middleware.Static (staticPolicy, addBase)
import Web.Scotty (ScottyM, ActionM, middleware, scotty, get, post, literal)

-- | The application monad.
type LurkApp = ScottyM ()

-- | The action monad for request handling.
type Action = ActionM ()

data RouteOption
    = TrailingSlashes       -- ^ Enforce trailing slashes on page routes (301)
    | ServeStatic FilePath  -- ^ Serve a directory of static assets

-- | Apply a list of route-level settings. Call at the top of your router.
routeSettings :: [RouteOption] -> LurkApp
routeSettings = mapM_ apply
  where
    apply TrailingSlashes    = middleware trailingSlash
    apply (ServeStatic dir)  = middleware $ staticPolicy (addBase dir)

-- | Start the Lurk application on the given port.
runLurk :: Int -> LurkApp -> IO ()
runLurk = scotty

-- | Register a single page route.
getPage :: Text -> Action -> LurkApp
getPage path action = get (literal $ T.unpack path) action

-- | Register a page route for each value in a list (multi-language).
getPages :: [lang] -> (lang -> Text) -> (lang -> Action) -> LurkApp
getPages langs pathFn actionFn =
    mapM_ (\lang -> getPage (pathFn lang) (actionFn lang)) langs

-- | Register a post action (form submission, API call, etc).
postAction :: Text -> Action -> LurkApp
postAction path action = post (literal $ T.unpack path) action
