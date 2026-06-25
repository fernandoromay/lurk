module Lurk.App
    ( Config(..)
    , LurkApp
    , runLurk
    , getStore
    , getAppEnv
    ) where

import Control.Concurrent.STM (TVar, newTVarIO, readTVarIO, atomically, writeTVar)
import Data.Text (Text)
import System.IO.Unsafe (unsafePerformIO)
import Lurk.Session (SessionStore, newFileSessionStore, cleanupSessions)
import Lurk.Session.Middleware (sessionMiddleware)
import Lurk.CSRF (csrfMiddleware)
import Lurk.Env (Env)
import qualified Lurk.Env
import Web.Scotty (ScottyM, middleware, scotty)

-- | Application configuration
data Config = Config
    { port          :: Int
    , domain        :: Text
    , sessionMaxAge :: Maybe Int
    , sessionIdle   :: Maybe Int
    }

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



-- Start the Lurk application
runLurk :: Config -> LurkApp -> IO ()
runLurk cfg app = do
    env <- Lurk.Env.loadEnv
    atomically $ writeTVar envRef (Just env)
    store <- newFileSessionStore (sessionMaxAge cfg) (sessionIdle cfg) ".lurk-sessions"
    atomically $ writeTVar storeRef (Just store)
    _ <- cleanupSessions store
    scotty (port cfg) $ do
        middleware (sessionMiddleware store)
        middleware (csrfMiddleware store)
        app
