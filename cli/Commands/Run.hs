{-# LANGUAGE OverloadedStrings #-}
module Commands.Run
    ( runProject
    , buildProject
    ) where

import Lurk.Env (loadEnv)
import Shared (updateCabalModules, safeCallProcess)
import qualified Log

runProject :: IO ()
runProject = do
    loadEnv
    updateCabalModules
    putStrLn "Starting LURK dev server..."
    result <- safeCallProcess "cabal" ["run", "-v0"]
    case result of
        Left err -> Log.logError err
        Right () -> pure ()

buildProject :: IO ()
buildProject = do
    loadEnv
    updateCabalModules
    putStrLn "Building project..."
    result <- safeCallProcess "cabal" ["build", "-v0"]
    case result of
        Left err -> Log.logError err
        Right () -> pure ()
