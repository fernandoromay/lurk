{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
module Commands.Deploy.Core
    ( DeployProvider(..)
    , DeployError(..)
    , DeployConfig(..)
    , DeploySettings(..)
    , loadDeployConfig
    , saveDeployConfig
    , generateEnvContent
    , getEnvKeysFromSource
    , getProjectName
    , resolveEnvVars
    ) where

import GHC.Generics (Generic)
import Data.Aeson (FromJSON, ToJSON, Value(..))
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import qualified Data.Yaml as Yaml
import qualified Data.Map as Map
import qualified Data.Vector as V
import System.Environment (lookupEnv)
import Data.Maybe (fromMaybe)
import System.Directory (doesFileExist, listDirectory)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Control.Monad (filterM, foldM)
import Data.List (isPrefixOf, isSuffixOf)

-- | Interface for different deployment methods
class DeployProvider p where
    setup    :: p -> IO (Either DeployError ())
    validate :: p -> IO (Either DeployError ())
    package  :: p -> IO (Either DeployError FilePath)
    transfer :: p -> FilePath -> Maybe FilePath -> IO (Either DeployError ())
    activate :: p -> IO (Either DeployError ())
    rollback :: p -> IO (Either DeployError ())

-- | Generate the content of the .env file based on the mapping and system env
generateEnvContent :: Map.Map String String -> IO String
generateEnvContent mapping = do
    pairs <- mapM (\(envKey, envVar) -> do
        val <- lookupEnv envVar
        pure $ envKey ++ "=" ++ fromMaybe "" val
        ) (Map.toList mapping)
    pure $ unlines pairs

-- | Extract keys from .env or .example.env
getEnvKeysFromSource :: IO [String]
getEnvKeysFromSource = do
    let files = [".env", ".example.env"]
    existingFiles <- filterM doesFileExist files
    case existingFiles of
        [] -> pure []
        (f:_) -> do
            content <- TIO.readFile f
            pure $ map (T.unpack . T.strip . fst . T.breakOn "=") $ filter (not . T.null) $ T.lines content

data DeployError
    = ConfigError String
    | ValidationError String
    | PackagingError String
    | TransferError String
    | ActivationError String
    deriving (Show)

data DeployConfig = DeployConfig
    { project  :: String
    , build    :: Value
    , deploy   :: DeploySettings
    } deriving (Show, Generic)

data DeploySettings = DeploySettings
    { provider :: String
    , config   :: Value
    , env_vars :: Maybe (Map.Map String String)
    } deriving (Show, Generic)


instance FromJSON DeployConfig
instance FromJSON DeploySettings
instance ToJSON DeployConfig
instance ToJSON DeploySettings

-- | Load deployment configuration from lurk.yaml
loadDeployConfig :: FilePath -> IO (Either DeployError DeployConfig)
loadDeployConfig path = do
    result <- Yaml.decodeFileEither path
    case result of
        Left err -> pure $ Left $ ConfigError (show err)
        Right cfg -> pure $ Right cfg

-- | Save deployment configuration to lurk.yaml
saveDeployConfig :: FilePath -> DeployConfig -> IO (Either DeployError ())
saveDeployConfig path cfg = do
    Yaml.encodeFile path cfg
    pure $ Right ()

-- | Read project name from the first .cabal file's name: field
getProjectName :: IO String
getProjectName = do
    files <- listDirectory "."
    let cabalFiles = filter (".cabal" `isSuffixOf`) files
    case cabalFiles of
        [] -> pure "my-project"
        (f:_) -> do
            content <- TIO.readFile f
            let nameLines = filter (\l -> "name:" `T.isPrefixOf` T.strip l) (T.lines content)
            case nameLines of
                (line:_) -> do
                    let val = T.strip $ T.drop 1 $ snd $ T.breakOn ":" line
                    pure $ if T.null val then "my-project" else T.unpack val
                [] -> pure "my-project"

-- | Resolve ${VAR} placeholders in a JSON Value from the environment
-- Returns Left with all missing var names if any are unresolved
resolveEnvVars :: Value -> IO (Either [String] Value)
resolveEnvVars val = do
    (missing, resolved) <- go [] val
    if null missing
        then pure $ Right resolved
        else pure $ Left (reverse missing)
  where
    go acc (String s) = do
        let refs = extractVarRefs s
        (acc', s') <- resolveString acc refs s
        pure (acc', String s')
    go acc (Object m) = do
        let pairs = KeyMap.toList m
        (acc', pairs') <- foldM (\(a', ps) (k, v) -> do
            (a'', v') <- go a' v
            pure (a'', ps ++ [(k, v')])) (acc, []) pairs
        pure (acc', Object (KeyMap.fromList pairs'))
    go acc (Array a) = do
        (acc', elems') <- foldM (\(a', es) e -> do
            (a'', e') <- go a' e
            pure (a'', es ++ [e'])) (acc, []) (V.toList a)
        pure (acc', Array (V.fromList elems'))
    go acc v = pure (acc, v)

    resolveString acc [] s = pure (acc, s)
    resolveString acc ((varName, ref):refs) s = do
        mVal <- lookupEnv varName
        case mVal of
            Just val -> resolveString acc refs (T.replace ref (T.pack val) s)
            Nothing -> resolveString (varName : acc) refs s

    extractVarRefs s = go' [] s
      where
        go' acc t
          | T.null t = reverse acc
          | "${" `T.isPrefixOf` t =
              let rest = T.drop 2 t
                  (varName, after) = T.breakOn "}" rest
              in if T.null after
                  then reverse acc
                  else go' ((T.unpack varName, "${" <> varName <> "}") : acc) (T.drop 1 after)
          | otherwise = go' acc (T.drop 1 t)
