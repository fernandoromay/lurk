{-# LANGUAGE CPP #-}
module Lurk.App
    ( AppConfig(..)
    , appConfig
    , LurkApp
    , runLurk
    , LogLevel (..)
    , getDbPool
    ) where

import Control.Concurrent (killThread)
import Data.Text (Text)
import Data.Text qualified as T
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.IO.Unsafe (unsafePerformIO)
import Lurk.Log (LogLevel(..), levelToText)
import Lurk.Session (newFileSessionStore, cleanupSessions, storeVaultMiddleware)
import Lurk.Session.Middleware (sessionMiddleware)
import Lurk.CSRF (csrfMiddleware)
import Lurk.Error (errorMiddleware)
import qualified Lurk.Env
import Lurk.DB.Config (DbConfig(..))
import Lurk.DB.Pool (Pool, newPool, destroyPool)
import qualified Lurk.DB.Migration as Migration
import Database.SQLite.Simple (Connection)
import System.Environment (setEnv)
import System.IO (hFlush, stdout)
import Web.Scotty (ScottyM, middleware, scottyApp)
import Network.Wai.Handler.Warp qualified as Warp

#if !defined(mingw32_HOST_OS)
import System.Posix.Signals (installHandler, sigINT, sigTERM, Handler(Catch))
#endif

-- | Global reference to the database pool (if configured).
{-# NOINLINE dbPoolRef #-}
dbPoolRef :: IORef (Maybe (Pool Connection))
dbPoolRef = unsafePerformIO (newIORef Nothing)

-- | Get the database pool. Returns Nothing if no database is configured.
-- Call this from route handlers to access the DB.
getDbPool :: IO (Maybe (Pool Connection))
getDbPool = readIORef dbPoolRef

-- | Application configuration
data AppConfig = AppConfig
    { port          :: Int
    , domain        :: Text
    , sessionMaxAge :: Maybe Int
    , sessionIdle   :: Maybe Int
    , minLogLevel   :: LogLevel
    , database      :: Maybe DbConfig
    }

-- | Default configuration. Override only the fields you need.
--
-- @
-- main = do
--     loadEnv
--     let cfg = (appConfig "example.com") { port = 3003 }
--     runLurk cfg router
-- @
appConfig :: AppConfig
appConfig = AppConfig
    { port          = 3000
    , domain        = ""
    , sessionMaxAge = Nothing
    , sessionIdle   = Nothing
    , minLogLevel   = LevelInfo
    , database      = Nothing
    }

-- | The application monad.
type LurkApp = ScottyM ()

-- Start the Lurk application
runLurk :: AppConfig -> LurkApp -> IO ()
runLurk cfg app = do
    Lurk.Env.loadEnv
    setEnv "LURK_LOG_LEVEL" (T.unpack (levelToText (minLogLevel cfg)))
    store <- newFileSessionStore (sessionMaxAge cfg) (sessionIdle cfg) ".lurk-sessions"
    cleanupThreadId <- cleanupSessions store

    -- Initialize database pool if configured
    mPool <- case database cfg of
        Nothing -> pure Nothing
        Just dbCfg -> do
            putStrLn "Initializing database pool..."
            hFlush stdout
            pool <- newPool dbCfg
            writeIORef dbPoolRef (Just pool)
            -- Auto-migrate if configured
            if dbAutoMigrate dbCfg
                then do
                    putStrLn "Running pending migrations..."
                    hFlush stdout
                    Migration.migrate pool "migrations"
                else pure ()
            pure (Just pool)

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

    -- Cleanup
#if !defined(mingw32_HOST_OS)
    putStrLn "Running cleanup tasks..."
    hFlush stdout
#endif
    killThread cleanupThreadId
    -- Destroy database pool
    case mPool of
        Nothing -> pure ()
        Just pool -> do
            putStrLn "Closing database connections..."
            hFlush stdout
            destroyPool pool
    putStrLn "LURK stopped successfully."
    hFlush stdout
