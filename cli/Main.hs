{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs)
import Data.Maybe (fromMaybe)

import qualified Commands.Run as Run
import qualified Commands.Deploy as DeployCmd
import qualified Commands.Kill as Kill
import qualified Commands.New as New
import qualified Commands.AddPage as AddPage

data Command
    = Run
    | Build
    | Deploy Bool       -- ^ --init flag
    | Kill (Maybe String)
    | New String
    | AddPage (Maybe String)
    | Help

parseCommand :: [String] -> Either String Command
parseCommand ["run"] = Right Run
parseCommand ["build"] = Right Build
parseCommand ["deploy"] = Right (Deploy False)
parseCommand ["deploy", "--init"] = Right (Deploy True)
parseCommand ["kill"] = Right (Kill Nothing)
parseCommand ["kill", p] = Right (Kill (Just p))
parseCommand ["new", t] = Right (New t)
parseCommand ["add", "page"] = Right (AddPage Nothing)
parseCommand ["add", "page", n] = Right (AddPage (Just n))
parseCommand ["--help"] = Right Help
parseCommand ["-h"] = Right Help
parseCommand [] = Right Help
parseCommand args = Left $ "Unknown command: " ++ unwords args

main :: IO ()
main = do
    args <- getArgs
    case parseCommand args of
        Left err -> do
            putStrLn $ "Error: " ++ err
            putStrLn "Run 'lurk --help' for usage."
        Right Help -> putStrLn usage
        Right cmd -> dispatch cmd

dispatch :: Command -> IO ()
dispatch Run = Run.runProject
dispatch Build = Run.buildProject
dispatch (Deploy init) = if init then DeployCmd.initCommand else DeployCmd.deployCommand
dispatch (Kill mp) = case mp of
    Nothing -> Kill.killCommand
    Just p  -> Kill.killPort p
dispatch (New t) = New.newProject t
dispatch (AddPage mn) = AddPage.addPage (fromMaybe "" mn)

usage :: String
usage = unlines
    [ "Usage: lurk <command>"
    , ""
    , "Commands:"
    , "  run              Start dev server"
    , "  build            Build project"
    , "  deploy           Deploy via SSH or Docker"
    , "  deploy --init    Initialize deployment config"
    , "  kill [port]      Kill process on port"
    , "  new <type>       Scaffold a new project"
    , "  add page [name]  Add a new page"
    , "  --help           Show this help"
    ]
