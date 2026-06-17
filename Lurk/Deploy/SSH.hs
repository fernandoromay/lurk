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
import System.Process (callProcess)
import System.Exit (ExitCode(..))

data SSHConfig = SSHConfig
    { host         :: String
    , user         :: String
    , path         :: FilePath
    , activate_cmd :: String
    } deriving (Show, Generic)

instance FromJSON SSHConfig

data SSHProvider = SSHProvider SSHConfig

instance DeployProvider SSHProvider where
    validate (SSHProvider cfg) = do
        putStrLn $ "Validating SSH connection to " ++ host cfg ++ "..."
        pure $ Right ()

    package (SSHProvider _) = do
        putStrLn "Packaging project..."
        callProcess "cabal" ["build", "--minimize"]
        pure $ Right ()

    transfer (SSHProvider cfg) mEnvPath = do
        putStrLn $ "Transferring files to " ++ host cfg ++ "..."
        let binaryName = "ruzaani-website"
        let remoteDest = user cfg ++ "@" ++ host cfg ++ ":" ++ path cfg
        
        -- Create backup of existing binary on remote
        putStrLn "Creating remote backup..."
        _ <- callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "mv " ++ path cfg ++ "/" ++ binaryName ++ " " ++ path cfg ++ "/" ++ binaryName ++ ".bak"]
        
        -- Transfer new binary and public
        let binaryPath = "dist-newstyle/build/x86_64-linux/ghc-9.4.8/website-0.1.0.0/x/ruzaani-website/build/ruzaani-website/ruzaani-website"
        callProcess "rsync" ["-avz", binaryPath, "public/", remoteDest]
        
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
        let binaryName = "ruzaani-website"
        callProcess "ssh" [(user cfg ++ "@" ++ host cfg), "mv " ++ path cfg ++ "/" ++ binaryName ++ ".bak " ++ path cfg ++ "/" ++ binaryName ++ " && " ++ activate_cmd cfg]
        pure $ Right ()
