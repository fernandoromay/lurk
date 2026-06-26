module Lurk.App
    ( Config(..)
    , LurkApp
    , runLurk
    , LogLevel (..)
    ) where

import Data.Text (Text)
import Data.Text qualified as T
import Lurk.Log (LogLevel(..), levelToText)
import Lurk.Session (newFileSessionStore, cleanupSessions, storeVaultMiddleware)
import Lurk.Session.Middleware (sessionMiddleware)
import Lurk.CSRF (csrfMiddleware)
import Lurk.Error (errorMiddleware)
import qualified Lurk.Env
import System.Environment (setEnv)
import Web.Scotty (ScottyM, middleware, scotty)

-- | Application configuration
data Config = Config
    { port          :: Int
    , domain        :: Text
    , sessionMaxAge :: Maybe Int
    , sessionIdle   :: Maybe Int
    , minLogLevel   :: LogLevel
    }

-- | The application monad.
type LurkApp = ScottyM ()

-- Start the Lurk application
runLurk :: Config -> LurkApp -> IO ()
runLurk cfg app = do
    Lurk.Env.loadEnv
    setEnv "LURK_LOG_LEVEL" (T.unpack (levelToText (minLogLevel cfg)))
    store <- newFileSessionStore (sessionMaxAge cfg) (sessionIdle cfg) ".lurk-sessions"
    _ <- cleanupSessions store
    scotty (port cfg) $ do
        middleware errorMiddleware
        middleware (storeVaultMiddleware store)
        middleware (sessionMiddleware store)
        middleware (csrfMiddleware store)
        app
