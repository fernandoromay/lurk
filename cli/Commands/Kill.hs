{-# LANGUAGE OverloadedStrings #-}
module Commands.Kill
    ( killCommand
    , killPort
    ) where

import System.Process (rawSystem, readProcess)
import System.Environment (lookupEnv)
import System.Directory (doesFileExist)
import System.Info (os)
import Control.Monad (unless)
import Data.List (isInfixOf)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Shared (loadDotEnv)

-- | Entry point for the kill command (auto-detect port)
killCommand :: IO ()
killCommand = do
    port <- detectPort
    killPort port

killPort :: String -> IO ()
killPort port = do
    putStrLn $ "Killing processes holding port " ++ port ++ "..."
    case os of
        "mingw32" -> do
            output <- readProcess "netstat" ["-ano"] ""
            let matchingLines = filter (portPattern port) (lines output)
                pids = map (last . words) matchingLines
            mapM_ (\pid -> rawSystem "taskkill" ["/F", "/PID", pid]) pids
        "darwin" -> do
            pids <- readProcess "lsof" ["-t", "-i", ":" ++ port] ""
            mapM_ (\pid -> unless (null pid) $ do
                _ <- rawSystem "kill" ["-9", pid]
                pure ()) (lines pids)
        _ -> do
            _ <- rawSystem "fuser" ["-k", port ++ "/tcp"]
            return ()
  where
    portPattern p line = (":" ++ p) `isInfixOf` line

detectPort :: IO String
detectPort = do
    loadDotEnv
    mEnvPort <- lookupEnv "PORT"
    case mEnvPort of
        Just p -> pure p
        Nothing -> do
            exists <- doesFileExist "Config.hs"
            if not exists
                then pure "3000"
                else do
                    content <- TIO.readFile "Config.hs"
                    let linesOfContent = T.lines content
                        findVal = filter (\line -> "defaultPort =" `T.isInfixOf` line) linesOfContent
                    case findVal of
                        (line:_) -> do
                            let val = T.strip $ snd $ T.breakOn "=" line
                            pure $ T.unpack val
                        [] -> pure "3000"
