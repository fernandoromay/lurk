{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs)

import qualified Commands.Run as Run
import qualified Commands.Deploy as DeployCmd
import qualified Commands.Kill as Kill
import qualified Commands.New as New
import qualified Commands.AddPage as AddPage

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["run"] -> Run.runProject
        ["build"] -> Run.buildProject
        ["deploy"] -> DeployCmd.deployCommand
        ["deploy", "--init"] -> DeployCmd.initCommand
        ["kill"] -> Kill.killCommand
        ["kill", port] -> Kill.killPort port
        ["new", scaffoldType] -> New.newProject scaffoldType
        ["add", "page"] -> AddPage.addPage ""
        ["add", "page", name] -> AddPage.addPage name
        _ -> putStrLn "Usage: lurk run | lurk build | lurk deploy | lurk deploy --init | lurk kill [port] | lurk new <type> | lurk add page [name]"
