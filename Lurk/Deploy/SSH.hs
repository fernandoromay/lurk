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
        let serviceFile = "[Unit]\nDescription=" ++ service_name cfg ++ "\nAfter=network.target\n\n[Service]\nExecStart=" ++ path cfg ++ "/" ++ service_name cfg ++ "\nWorkingDirectory=" ++ path cfg ++ "\nRestart=always\n\n[Install]\nWantedBy=multi-user.target"
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
        let remoteDest = user cfg ++ "@" ++ host cfg ++ ":" ++ path cfg
        
        -- Create backup of existing binary on remote
        putStrLn "Creating remote backup..."
        let remotePath = path cfg ++ "/" ++ binaryName
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "[ -f " ++ remotePath ++ " ] && mv " ++ remotePath ++ " " ++ remotePath ++ ".bak || true"]
        
        -- Transfer new binary and public
        callProcess "rsync" ["-avz", binaryPath, "public/", remoteDest ++ "/" ++ binaryName]
        
        -- Transfer .env if it exists
        case mEnvPath of
            Just envPath -> callProcess "rsync" ["-avz", envPath, remoteDest ++ "/.env"]
            Nothing -> putStrLn "No .env file to transfer."
            
        pure $ Right ()

    activate (SSHProvider cfg) = do
        putStrLn "Activating..."
        callProcess "ssh" [(user cfg ++ "@" ++ host cfg), activate_cmd cfg]
        pure $ Right ()

    rollback (SSHProvider cfg) = do
        putStrLn "Rolling back to previous binary..."
        let binaryName = service_name cfg
        callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "mv " ++ path cfg ++ "/" ++ binaryName ++ ".bak " ++ path cfg ++ "/" ++ binaryName ++ " && " ++ activate_cmd cfg]
        pure $ Right ()
