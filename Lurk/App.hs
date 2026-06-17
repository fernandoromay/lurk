module Lurk.App
    ( LurkApp
    , Action
    , RouteOption(..)
    , routeSettings
    , runLurk
    , getPage
    , getPages
    , postAction
    , getStore
    ) where

import Control.Concurrent.STM (TVar, newTVarIO, readTVarIO, atomically, writeTVar)
import Data.Text (Text)
import qualified Data.Text as T
import System.IO.Unsafe (unsafePerformIO)
import Lurk.Routes (trailingSlash)
import Lurk.Session (SessionStore, newFileSessionStore)
import Lurk.Session.Middleware (sessionMiddleware)
import Lurk.CSRF (csrfMiddleware)
import Network.Wai.Middleware.Static (staticPolicy, addBase)
import Web.Scotty (ScottyM, ActionM, middleware, scotty, get, post, literal)

-- | Global store reference (set during startup, read by handlers)
{-# NOINLINE storeRef #-}
storeRef :: TVar (Maybe SessionStore)
storeRef = unsafePerformIO $ newTVarIO Nothing

-- | Get the session store (for use in handlers)
getStore :: IO SessionStore
getStore = do
    ms <- readTVarIO storeRef
    case ms of
        Just s -> pure s
        Nothing -> error "Lurk.App.getStore: session store not initialized"

-- | The application monad.
type LurkApp = ScottyM ()

-- | The action monad for request handling
type Action a = ActionM a

data RouteOption
    = TrailingSlashes       -- ^ Enforce trailing slashes
    | ServeStatic FilePath  -- ^ Serve a dir of static assets

-- Apply a list of route-level settings
routeSettings :: [RouteOption] -> LurkApp
routeSettings = mapM_ apply
  where
    apply TrailingSlashes    = middleware trailingSlash
    apply (ServeStatic dir)  = middleware $ staticPolicy (addBase dir)

-- Start the Lurk application on the given port
runLurk :: Int -> LurkApp -> IO ()
runLurk port app = do
    store <- newFileSessionStore ".lurk-sessions"
    atomically $ writeTVar storeRef (Just store)
    scotty port $ do
        middleware (sessionMiddleware store)
        middleware (csrfMiddleware store)
        app

-- Register a single page
getPage :: Text -> Action () -> LurkApp
getPage path = get (literal $ T.unpack path)

-- | Register a page route for each value in a list (multi-language).
getPages :: [lang] -> (lang -> Text) -> (lang -> Action()) -> LurkApp
getPages langs pathFn actionFn =
    mapM_ (\lang -> getPage (pathFn lang) (actionFn lang)) langs

-- Register a post action
postAction :: Text -> Action () -> LurkApp
postAction path = post (literal $ T.unpack path)
