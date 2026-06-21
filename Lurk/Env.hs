-- | Load environment variables from a @.env@ file and provide typed access.
--
-- @
-- env <- loadEnv
-- host <- requireEnv env "DB_HOST"
-- port <- getEnv env "DB_PORT"  -- Maybe Text
-- @
module Lurk.Env
    ( Env
    , loadEnv
    , loadEnvFile
    , getEnv
    , getEnvWithDefault
    , getEnvInt
    , getEnvBool
    , requireEnv
    , hasEnv
    ) where

import Data.Maybe (fromMaybe)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Environment (lookupEnv, setEnv)
import System.Directory (doesFileExist)

-- | Opaque environment. Use 'getEnv' or 'requireEnv' to read values.
newtype Env = Env (Map Text Text)

-- | Load \".env\" from the working directory and return the environment.
loadEnv :: IO Env
loadEnv = loadEnvFile ".env"

-- | Load a @.env@ file from the given path.
loadEnvFile :: FilePath -> IO Env
loadEnvFile path = do
    exists <- doesFileExist path
    fileVars <- if not exists then pure Map.empty else do
        contents <- TIO.readFile path
        pure $ Map.fromList $ mapMaybe parse (T.lines contents)
    -- Set each var in process env (skip if already set)
    mapM_ (uncurry setIfMissing) (Map.toList fileVars)
    -- Build Env: for each key, prefer process env over .env
    resolved <- mapM (resolveKey fileVars) (Map.keys fileVars)
    pure (Env (Map.fromList resolved))

resolveKey :: Map Text Text -> Text -> IO (Text, Text)
resolveKey fileVars key = do
    mVal <- lookupEnv (T.unpack key)
    case mVal of
        Just v  -> pure (key, T.pack v)
        Nothing -> pure (key, fileVars Map.! key)

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
getEnv :: Env -> Text -> Maybe Text
getEnv (Env m) key = Map.lookup key m

-- | Look up a variable. Fails with a clear error if missing.
requireEnv :: Env -> Text -> IO Text
requireEnv env key = case getEnv env key of
    Just val -> pure val
    Nothing  -> error $ "Missing required env var: " ++ T.unpack key

-- | Check if a variable exists.
hasEnv :: Env -> Text -> Bool
hasEnv (Env m) key = Map.member key m

-- | Look up a variable with a default value.
getEnvWithDefault :: Env -> Text -> Text -> Text
getEnvWithDefault env key def = fromMaybe def (getEnv env key)

-- | Look up a variable and parse it as Int. Returns Nothing if missing or unparseable.
getEnvInt :: Env -> Text -> Maybe Int
getEnvInt env key = case getEnv env key of
    Nothing -> Nothing
    Just val -> case reads (T.unpack val) of
        [(x, "")] -> Just x
        _         -> Nothing

-- | Look up a variable and parse it as Bool. Returns Nothing if missing or unparseable.
-- Accepts @true@, @false@, @1@, @0@ (case-insensitive).
getEnvBool :: Env -> Text -> Maybe Bool
getEnvBool env key = case getEnv env key of
    Nothing -> Nothing
    Just val -> case T.toLower (T.strip val) of
        "true"  -> Just True
        "false" -> Just False
        "1"     -> Just True
        "0"     -> Just False
        _       -> Nothing
