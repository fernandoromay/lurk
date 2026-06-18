module Lurk.App
    ( LurkApp
    , Action
    , RouteOption(..)
    , routeSettings
    , runLurk
    , getPage
    , getPages
    , postAction
    , postActions
    , getStore
    , getAppEnv
    ) where

import Control.Concurrent.STM (TVar, newTVarIO, readTVarIO, atomically, writeTVar)
import Data.Text (Text)
import qualified Data.Text as T
import System.IO.Unsafe (unsafePerformIO)
import System.Environment (lookupEnv)
import Lurk.Routes (trailingSlash)
import Lurk.Session (SessionStore, newFileSessionStore)
import Lurk.Session.Middleware (sessionMiddleware)
import Lurk.CSRF (csrfMiddleware)
import Lurk.Env (Env)
import qualified Lurk.Env
import Network.Wai.Middleware.Static (staticPolicy, addBase)
import Network.Wai.Middleware.ForceSSL (forceSSL)
import Network.Wai (Middleware)
import Web.Scotty (ScottyM, ActionM, middleware, scotty, get, post, literal)

-- | Global store reference (set during startup, read by handlers)
{-# NOINLINE storeRef #-}
storeRef :: TVar (Maybe SessionStore)
storeRef = unsafePerformIO $ newTVarIO Nothing

-- | Global env reference (set during startup, read by handlers)
{-# NOINLINE envRef #-}
envRef :: TVar (Maybe Env)
envRef = unsafePerformIO $ newTVarIO Nothing

-- | Get the session store (for use in handlers)
getStore :: IO SessionStore
getStore = do
    ms <- readTVarIO storeRef
    case ms of
        Just s -> pure s
        Nothing -> error "Lurk.App.getStore: session store not initialized"

-- | Get the app environment (for use in handlers)
getAppEnv :: IO Env
getAppEnv = do
    me <- readTVarIO envRef
    case me of
        Just e -> pure e
        Nothing -> error "Lurk.App.getAppEnv: env not initialized"

-- | The application monad.
type LurkApp = ScottyM ()

-- | The action monad for request handling
type Action a = ActionM a

data RouteOption
    = TrailingSlashes       -- ^ Enforce trailing slashes
    | ForceSSL              -- ^ Redirect HTTP to HTTPS
    | ServeStatic FilePath  -- ^ Serve a dir of static assets

-- | A smarter ForceSSL that only runs in production
smartForceSSL :: Middleware
smartForceSSL app req respond = do
    env <- lookupEnv "LURK_ENV"
    if env == Just "production"
        then forceSSL app req respond
        else app req respond

-- Apply a list of route-level settings
routeSettings :: [RouteOption] -> LurkApp
routeSettings = mapM_ apply
  where
    apply TrailingSlashes    = middleware trailingSlash
    apply ForceSSL           = middleware smartForceSSL
    apply (ServeStatic dir)  = middleware $ staticPolicy (addBase dir)

-- Start the Lurk application on the given port
runLurk :: Int -> LurkApp -> IO ()
runLurk port app = do
    env <- Lurk.Env.loadEnv
    atomically $ writeTVar envRef (Just env)
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

-- | Register a post action for each value in a list (multi-language).
postActions :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
postActions langs pathFn actionFn =
    mapM_ (\lang -> postAction (pathFn lang) (actionFn lang)) langs
