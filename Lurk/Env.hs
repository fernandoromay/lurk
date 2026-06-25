-- | Load environment variables from a @.env@ file and provide typed access.
--
-- @
-- loadEnv
-- host <- requireEnv "DB_HOST"
-- port <- getEnv "DB_PORT"  -- IO (Maybe Text)
-- @
module Lurk.Env
    ( loadEnv
    , loadEnvFile
    , getEnv
    , getEnvWithDefault
    , getEnvInt
    , getEnvBool
    , requireEnv
    , hasEnv
    ) where

import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Environment (lookupEnv, setEnv)
import System.Directory (doesFileExist)

-- | Load \".env\" from the working directory.
loadEnv :: IO ()
loadEnv = loadEnvFile ".env"

-- | Load a @.env@ file from the given path. Sets environment variables if missing.
loadEnvFile :: FilePath -> IO ()
loadEnvFile path = do
    exists <- doesFileExist path
    if not exists then pure () else do
        contents <- TIO.readFile path
        let fileVars = mapMaybe parse (T.lines contents)
        -- Set each var in process env (skip if already set)
        mapM_ (uncurry setIfMissing) fileVars

setIfMissing :: Text -> Text -> IO ()
setIfMissing key val = do
    existing <- lookupEnv (T.unpack key)
    case existing of
        Nothing -> setEnv (T.unpack key) (T.unpack val)
        Just _  -> pure ()

parse :: Text -> Maybe (Text, Text)
parse raw =
    let stripped = T.strip raw
    in if T.null stripped || T.head stripped == '#'
        then Nothing
        else case T.breakOn "=" stripped of
            (k, v) | not (T.null v) -> Just (T.strip k, unquote (T.tail v))
            _ -> Nothing

unquote :: Text -> Text
unquote t
    | T.length t >= 2, T.head t == '"', T.last t == '"' = T.init (T.tail t)
    | T.length t >= 2, T.head t == '\'', T.last t == '\'' = T.init (T.tail t)
    | otherwise = t

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe _ [] = []
mapMaybe f (x:xs) = case f x of
    Just y  -> y : mapMaybe f xs
    Nothing -> mapMaybe f xs

-- | Look up a variable. Returns 'Nothing' if not set.
getEnv :: Text -> IO (Maybe Text)
getEnv key = do
    mVal <- lookupEnv (T.unpack key)
    pure (T.pack <$> mVal)

-- | Look up a variable. Fails with a clear error if missing.
requireEnv :: Text -> IO Text
requireEnv key = do
    mVal <- getEnv key
    case mVal of
        Just val -> pure val
        Nothing  -> error $ "Missing required env var: " ++ T.unpack key

-- | Check if a variable exists.
hasEnv :: Text -> IO Bool
hasEnv key = isJust <$> getEnv key

-- | Look up a variable with a default value.
getEnvWithDefault :: Text -> Text -> IO Text
getEnvWithDefault key def = fromMaybe def <$> getEnv key

-- | Look up a variable and parse it as Int. Returns Nothing if missing or unparseable.
getEnvInt :: Text -> IO (Maybe Int)
getEnvInt key = do
    mVal <- getEnv key
    case mVal of
        Nothing -> pure Nothing
        Just val -> case reads (T.unpack val) of
            [(x, "")] -> pure (Just x)
            _         -> pure Nothing

-- | Look up a variable and parse it as Bool. Returns Nothing if missing or unparseable.
-- Accepts @true@, @false@, @1@, @0@ (case-insensitive).
getEnvBool :: Text -> IO (Maybe Bool)
getEnvBool key = do
    mVal <- getEnv key
    case mVal of
        Nothing -> pure Nothing
        Just val -> case T.toLower (T.strip val) of
            "true"  -> pure (Just True)
            "false" -> pure (Just False)
            "1"     -> pure (Just True)
            "0"     -> pure (Just False)
            _       -> pure Nothing
