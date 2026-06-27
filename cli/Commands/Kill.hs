{-# LANGUAGE OverloadedStrings #-}
module Commands.Kill
    ( killCommand
    , killPort
    ) where

import System.Process (rawSystem)
import System.Environment (lookupEnv)
import System.Directory (doesFileExist)
import System.Info (os)
import Data.Char (isDigit)
import Control.Monad (unless)
import Data.List (isInfixOf)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Maybe (mapMaybe)

import Lurk.Env (loadEnv)
import Shared (safeReadProcess)

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
            result <- safeReadProcess "netstat" ["-ano"]
            case result of
                Left err -> putStrLn $ "Warning: " ++ err
                Right output -> do
                    let matchingLines = filter (portPattern port) (lines output)
                        pids = map (last . words) $ filter (not . null . words) matchingLines
                    mapM_ (\pid -> rawSystem "taskkill" ["/F", "/PID", pid]) pids
                    pure ()
        "darwin" -> do
            result <- safeReadProcess "lsof" ["-t", "-i", ":" ++ port]
            case result of
                Left err -> putStrLn $ "Warning: " ++ err
                Right pids ->
                    mapM_ (\pid -> unless (null pid) $ do
                        _ <- rawSystem "kill" ["-9", pid]
                        pure ()) (lines pids)
        _ -> do
            _ <- rawSystem "fuser" ["-k", port ++ "/tcp"]
            return ()
  where
    portPattern p line = (":" ++ p) `isInfixOf` line

-- | Detect port: Config record in Main.hs is the highest source of truth.
-- Priority: Main.hs Config port value -> env file lookup -> default 3000
detectPort :: IO String
detectPort = do
    exists <- doesFileExist "Main.hs"
    if not exists
        then pure "3000"
        else do
            content <- TIO.readFile "Main.hs"
            let portVal = findPortValue (T.lines content)
            case portVal of
                Nothing -> pure "3000"
                Just val
                    | all (\c -> isDigit c || c == ' ') (T.unpack val) ->
                        pure $ T.unpack $ T.strip val
                    | otherwise -> detectPortFromEnv val

-- | Find the port value from the Config record in Main.hs
-- Handles both "port = 3003" and "{ port = 3003" (record syntax)
findPortValue :: [T.Text] -> Maybe T.Text
findPortValue [] = Nothing
findPortValue (l:ls)
    | "port" `T.isPrefixOf` rest && "=" `T.isInfixOf` rest =
        let afterEq = T.strip $ T.drop 1 $ snd $ T.breakOn "=" rest
        in if T.null afterEq then findPortValue ls else Just afterEq
    | otherwise = findPortValue ls
  where
    stripped = T.stripStart l
    rest = case T.uncons stripped of
        Just ('{', remaining) -> T.stripStart remaining
        _ -> stripped

-- | If port value is a non-numeric env var ref, find the env file and look it up
detectPortFromEnv :: T.Text -> IO String
detectPortFromEnv varName = do
    content <- TIO.readFile "Main.hs"
    let envFile = findEnvFile (T.lines content)
    envVars <- parseEnvFile envFile
    case lookup (T.unpack varName) envVars of
        Just val -> pure val
        Nothing -> pure "3000"

-- | Find which env file Main.hs loads
findEnvFile :: [T.Text] -> FilePath
findEnvFile [] = ".env"
findEnvFile (l:ls)
    | "loadEnvFile" `T.isPrefixOf` stripped =
        let afterKw = T.strip $ T.drop 1 $ snd $ T.breakOn "\"" (T.strip l)
        in if T.length afterKw > 1 then T.unpack (T.init afterKw) else findEnvFile ls
    | "loadEnv" `T.isPrefixOf` stripped && not ("loadEnvFile" `T.isPrefixOf` stripped) = ".env"
    | otherwise = findEnvFile ls
  where stripped = T.strip l

-- | Parse a .env file into key-value pairs
parseEnvFile :: FilePath -> IO [(String, String)]
parseEnvFile path = do
    exists <- doesFileExist path
    if not exists then pure [] else do
        content <- TIO.readFile path
        pure $ mapMaybe parseLine (T.lines content)
  where
    parseLine l
        | T.null stripped = Nothing
        | "#" `T.isPrefixOf` stripped = Nothing
        | otherwise = case T.breakOn "=" stripped of
            (k, v) | not (T.null v) -> Just (T.unpack (T.strip k), T.unpack (T.strip (T.drop 1 v)))
            _ -> Nothing
      where stripped = T.strip l
