{-# LANGUAGE DeriveGeneric #-}
module Lurk.Deploy 
    ( DeployProvider(..)
    , DeployError(..)
    , DeployConfig(..)
    , DeploySettings(..)
    , loadDeployConfig
    , saveDeployConfig
    , generateEnvContent
    , getEnvKeysFromSource
    ) where

import GHC.Generics (Generic)
import Data.Aeson (FromJSON, ToJSON, Value)
import qualified Data.Yaml as Yaml
import qualified Data.Map as Map
import System.Environment (lookupEnv)
import Data.Maybe (fromMaybe)
import System.Directory (doesFileExist)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Control.Monad (filterM)

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
