{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs)
import System.Process (callProcess)

import Shared (loadDotEnv, updateCabalModules)
import qualified Commands.Kill as Kill
import qualified Commands.Deploy as DeployCmd
import qualified Commands.New as New
import qualified Commands.AddPage as AddPage

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["run"] -> runProject
        ["build"] -> buildProject
        ["deploy"] -> DeployCmd.deployCommand
        ["deploy", "--init"] -> DeployCmd.initCommand
        ["kill"] -> Kill.killCommand
        ["kill", port] -> Kill.killPort port
        ["new", scaffoldType] -> New.newProject scaffoldType
        ["add", "page"] -> AddPage.addPage ""
        ["add", "page", name] -> AddPage.addPage name
        _ -> putStrLn "Usage: lurk run | lurk build | lurk deploy | lurk deploy --init | lurk kill [port] | lurk new <type> | lurk add page [name]"

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
