{-# LANGUAGE OverloadedStrings #-}
module Commands.Run
    ( runProject
    , buildProject
    ) where

import System.Process (callProcess)

import Shared (loadDotEnv, updateCabalModules)

runProject :: IO ()
runProject = do
    loadDotEnv
    updateCabalModules
    putStrLn "Starting LURK dev server..."
    callProcess "cabal" ["run", "-v0"]

buildProject :: IO ()
buildProject = do
    loadDotEnv
    updateCabalModules
    putStrLn "Building project..."
    callProcess "cabal" ["build", "-v0"]
