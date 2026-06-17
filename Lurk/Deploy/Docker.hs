{-# LANGUAGE DeriveGeneric #-}
module Lurk.Deploy.Docker 
    ( DockerProvider(..)
    , DockerConfig(..)
    ) where

import Lurk.Deploy
import GHC.Generics (Generic)
import Data.Aeson (FromJSON)
import System.Process (readProcessWithExitCode, callProcess)
import System.Exit (ExitCode(..))

data DockerConfig = DockerConfig
    { registry   :: String
    , dockerfile :: FilePath
    , tag        :: String
    } deriving (Show, Generic)

instance FromJSON DockerConfig

data DockerProvider = DockerProvider DockerConfig

instance DeployProvider DockerProvider where
    validate _ = do
        putStrLn "Validating docker environment..."
        pure $ Right ()

    package (DockerProvider cfg) = do
        putStrLn $ "Building docker image: " ++ registry cfg ++ ":" ++ tag cfg
        callProcess "docker" ["build", "-t", registry cfg ++ ":" ++ tag cfg, "-f", dockerfile cfg, "--build-arg", "ENV_FILE=.env", "."]
        -- Tag as latest for transfer
        callProcess "docker" ["tag", registry cfg ++ ":" ++ tag cfg, registry cfg ++ ":latest"]
        pure $ Right ()

    transfer (DockerProvider cfg) _ = do
        putStrLn "Preparing backup in registry..."
        -- Pull existing latest to tag as previous
        _ <- readProcessWithExitCode "docker" ["pull", registry cfg ++ ":latest"] ""
        _ <- callProcess "docker" ["tag", registry cfg ++ ":latest", registry cfg ++ ":previous"]
        _ <- callProcess "docker" ["push", registry cfg ++ ":previous"]
        
        putStrLn $ "Pushing new image to registry: " ++ registry cfg
        callProcess "docker" ["push", registry cfg ++ ":" ++ tag cfg]
        callProcess "docker" ["push", registry cfg ++ ":latest"]
        pure $ Right ()

    activate (DockerProvider cfg) = do
        putStrLn "Activating new container..."
        -- Remove old container if exists
        _ <- readProcessWithExitCode "docker" ["rm", "-f", "lurk-app"] ""
        
        -- Run new container
        (code, _, err) <- readProcessWithExitCode "docker" ["run", "-d", "--name", "lurk-app", registry cfg ++ ":latest"] ""
        case code of
            ExitSuccess -> pure $ Right ()
            ExitFailure _ -> pure $ Left $ ActivationError err

    rollback (DockerProvider cfg) = do
        putStrLn "Rolling back to previous image..."
        _ <- callProcess "docker" ["rm", "-f", "lurk-app"]
        (code, _, err) <- readProcessWithExitCode "docker" ["run", "-d", "--name", "lurk-app", registry cfg ++ ":previous"] ""
        case code of
            ExitSuccess -> pure $ Right ()
            ExitFailure _ -> pure $ Left $ ActivationError err
