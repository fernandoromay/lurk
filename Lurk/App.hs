{-# LANGUAGE CPP #-}
module Lurk.App
    ( Config(..)
    , LurkApp
    , runLurk
    , LogLevel (..)
    ) where

import Control.Concurrent (killThread)
import Data.Text (Text)
import Data.Text qualified as T
import Lurk.Log (LogLevel(..), levelToText)
import Lurk.Session (newFileSessionStore, cleanupSessions, storeVaultMiddleware)
import Lurk.Session.Middleware (sessionMiddleware)
import Lurk.CSRF (csrfMiddleware)
import Lurk.Error (errorMiddleware)
import qualified Lurk.Env
import System.Environment (setEnv)
import System.IO (hFlush, stdout)
import Web.Scotty (ScottyM, middleware, scottyApp)
import Network.Wai.Handler.Warp qualified as Warp

#if !defined(mingw32_HOST_OS)
import System.Posix.Signals (installHandler, sigINT, sigTERM, Handler(Catch))
#endif

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
    cleanupThreadId <- cleanupSessions store

    waiApp <- scottyApp $ do
        middleware errorMiddleware
        middleware (storeVaultMiddleware store)
        middleware (sessionMiddleware store)
        middleware (csrfMiddleware store)
        app

    let warpSettings = 
            Warp.setPort (port cfg)
          $ Warp.setGracefulShutdownTimeout (Just 15)
          $ Warp.setInstallShutdownHandler (\closeSocket -> do
                let shutdownHandler = do
#if defined(mingw32_HOST_OS)
                        putStrLn "\nStopping new requests..."
                        hFlush stdout
#endif
                        closeSocket
#if !defined(mingw32_HOST_OS)
                _ <- installHandler sigINT (Catch shutdownHandler) Nothing
                _ <- installHandler sigTERM (Catch shutdownHandler) Nothing
#endif
                pure ()
            )
          $ Warp.defaultSettings

    putStrLn $ "LURK server running on http://localhost:" ++ show (port cfg)
    hFlush stdout
    Warp.runSettings warpSettings waiApp

#if !defined(mingw32_HOST_OS)
    putStrLn "Running cleanup tasks..."
    hFlush stdout
#endif
    killThread cleanupThreadId
    putStrLn "LURK stopped successfully."
    hFlush stdout
