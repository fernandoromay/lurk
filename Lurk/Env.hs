-- | Load environment variables from a @.env@ file into the process environment.
--
-- @loadEnv@ reads @.env@ from the working directory. Variables already present
-- in the environment are not overridden.
--
-- To load from a different path, use @loadEnvFile@:
--
-- @
-- loadEnvFile "config/secrets.env"
-- @
module Lurk.Env
    ( loadEnv
    , loadEnvFile
    ) where

import System.Environment (lookupEnv, setEnv)
import System.Directory (doesFileExist)
import Data.Char (isSpace)

-- | Load \".env\" from the working directory into the process environment.
-- Skips variables that are already set. Does nothing if the file doesn't exist.
loadEnv :: IO ()
loadEnv = loadEnvFile ".env"

-- | Load a @.env@ file from the given path.
loadEnvFile :: FilePath -> IO ()
loadEnvFile path = do
    exists <- doesFileExist path
    if not exists then pure () else do
        contents <- readFile path
        mapM_ (process . parse) (lines contents)
  where
    process ("", _) = pure ()
    process (key, val) = do
        existing <- lookupEnv key
        case existing of
            Nothing -> setEnv key val
            Just _  -> pure ()

    parse raw =
        let stripped = dropWhile isSpace raw
        in if null stripped || head stripped == '#'
            then ("", "")
            else case break (== '=') stripped of
                (k, '=':v) -> (rtrim k, unquote v)
                (k, v)     -> (rtrim k, unquote v)

    rtrim = reverse . dropWhile isSpace . reverse

    unquote ('"':s) | last s == '"' = init s
    unquote ('\'':s) | last s == '\'' = init s
    unquote s = s
