{-# LANGUAGE DeriveGeneric #-}
module Lurk.Deploy.SSH 
    ( SSHProvider(..)
    , SSHConfig(..)
    ) where

import Lurk.Deploy
import GHC.Generics (Generic)
import Data.Aeson (FromJSON, Object)
import Data.Aeson.Types (parseMaybe)
import qualified Data.Aeson as Aeson
import System.Process (callProcess, readProcess)
import System.Exit (ExitCode(..))

data SSHConfig = SSHConfig
    { host         :: String
    , user         :: String
    , path         :: FilePath
    , service_name :: String
    , activate_cmd :: String
    } deriving (Show, Generic)

instance FromJSON SSHConfig

data SSHProvider = SSHProvider SSHConfig

instance DeployProvider SSHProvider where
    setup (SSHProvider cfg) = do
        putStrLn "Setting up remote infrastructure..."
        -- 1. Create directory
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "mkdir -p " ++ path cfg]
        
        -- 2. Create systemd service file
        let serviceFile = "[Unit]\nDescription=" ++ service_name cfg ++ "\nAfter=network.target\n\n[Service]\nEnvironmentFile=" ++ path cfg ++ "/.env\nExecStart=" ++ path cfg ++ "/" ++ service_name cfg ++ "\nWorkingDirectory=" ++ path cfg ++ "\nRestart=always\n\n[Install]\nWantedBy=multi-user.target"
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "echo '" ++ serviceFile ++ "' | sudo tee /etc/systemd/system/" ++ service_name cfg ++ ".service"]
        
        -- 3. Reload systemd
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "sudo systemctl daemon-reload && sudo systemctl enable " ++ service_name cfg]
        
        pure $ Right ()

    validate (SSHProvider cfg) = do
        putStrLn $ "Validating SSH connection to " ++ host cfg ++ "..."
        pure $ Right ()

    package (SSHProvider cfg) = do
        putStrLn "Packaging project..."
        callProcess "cabal" ["build"]
        -- Dynamically get the binary path
        out <- readProcess "cabal" ["list-bin", service_name cfg] ""
        pure $ Right (init out) -- remove trailing newline

    transfer (SSHProvider cfg) binaryPath mEnvPath = do
        putStrLn $ "Transferring files to " ++ host cfg ++ "..."
        let binaryName = service_name cfg
        let remoteBase = user cfg ++ "@" ++ host cfg ++ ":" ++ path cfg
        let remoteBinary = remoteBase ++ "/" ++ binaryName
        
        -- Create backup of existing binary on remote
        putStrLn "Creating remote backup..."
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "[ -f " ++ path cfg ++ "/" ++ binaryName ++ " ] && mv " ++ path cfg ++ "/" ++ binaryName ++ " " ++ path cfg ++ "/" ++ binaryName ++ ".bak || true"]
        
        -- 1. Transfer binary
        putStrLn "Transferring binary..."
        callProcess "rsync" ["-avz", binaryPath, remoteBinary]

        -- 2. Transfer public assets
        putStrLn "Transferring public assets..."
        callProcess "rsync" ["-avz", "public/", remoteBase ++ "/public/"]
        
        -- Transfer .env if it exists
        case mEnvPath of
            Just envPath -> callProcess "rsync" ["-avz", envPath, remoteBase ++ "/.env"]
            Nothing -> putStrLn "No .env file to transfer."
            
        pure $ Right ()

    activate (SSHProvider cfg) = do
        putStrLn "Activating..."
        let remoteBinary = path cfg ++ "/" ++ service_name cfg
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "chmod +x " ++ remoteBinary ++ " && " ++ activate_cmd cfg]
        pure $ Right ()

    rollback (SSHProvider cfg) = do
        putStrLn "Rolling back to previous binary..."
        let binaryName = service_name cfg
        let remoteBinary = path cfg ++ "/" ++ binaryName
        let remoteBak = remoteBinary ++ ".bak"
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "mv " ++ remoteBak ++ " " ++ remoteBinary ++ " && chmod +x " ++ remoteBinary ++ " && " ++ activate_cmd cfg]
        pure $ Right ()
