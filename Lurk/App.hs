{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
module Lurk.App
    ( AppConfig(..)
    , appConfig
    , LurkApp
    , runLurk
    , LogLevel (..)
    , getDbPool
    , withSomeProvider
    , SomeProvider(..)
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
import Lurk.DB.Config (DbConfig(..), DbBackend(..))
import Lurk.DB.Core (DatabaseProvider, closeProvider)
import qualified Lurk.DB.Migration as Migration
import Lurk.DB.SQLite (SqliteProvider, newSqlitePool)
import Lurk.DB.Postgres (PostgresProvider, newPostgresPool)
import System.Environment (setEnv)
import System.IO (hFlush, stdout)
import Web.Scotty (ScottyM, middleware, scottyApp)
import Network.Wai.Handler.Warp qualified as Warp

#if !defined(mingw32_HOST_OS)
import System.Posix.Signals (installHandler, sigINT, sigTERM, Handler(Catch))
#endif

-- | Existential wrapper for database providers.
-- Hides the backend type so AppConfig can hold any provider.
data SomeProvider where
    SomeProvider :: DatabaseProvider db => db -> SomeProvider

-- | Apply a function to the hidden provider.
withSomeProvider :: SomeProvider -> (forall db. DatabaseProvider db => db -> IO a) -> IO a
withSomeProvider (SomeProvider db) f = f db

-- | Global reference to the database pool (if configured).
{-# NOINLINE dbPoolRef #-}
dbPoolRef :: IORef (Maybe SomeProvider)
dbPoolRef = unsafePerformIO (newIORef Nothing)

-- | Get the database pool. Returns Nothing if no database is configured.
getDbPool :: IO (Maybe SomeProvider)
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
            provider <- case dbBackend dbCfg of
                SQLite -> SomeProvider <$> newSqlitePool dbCfg
                PostgreSQL -> SomeProvider <$> newPostgresPool dbCfg
                MySQL -> error "MySQL backend not yet supported"
            writeIORef dbPoolRef (Just provider)
            -- Auto-migrate if configured
            if dbAutoMigrate dbCfg
                then do
                    putStrLn "Running pending migrations..."
                    hFlush stdout
                    case provider of
                        SomeProvider pool -> Migration.migrate pool "migrations"
                else pure ()
            pure (Just provider)

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
        Just (SomeProvider db) -> do
            putStrLn "Closing database connections..."
            hFlush stdout
            closeProvider db
    putStrLn "LURK stopped successfully."
    hFlush stdout
