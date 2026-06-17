{-# LANGUAGE DeriveGeneric #-}
module Lurk.Deploy.Shell 
    ( ShellProvider(..)
    , ShellConfig(..)
    ) where

import Lurk.Deploy
import GHC.Generics (Generic)
import Data.Aeson (FromJSON)
import System.Process (readProcessWithExitCode)
import System.Exit (ExitCode(..))

data ShellConfig = ShellConfig
    { script :: FilePath
    } deriving (Show, Generic)

instance FromJSON ShellConfig

data ShellProvider = ShellProvider ShellConfig

instance DeployProvider ShellProvider where
    validate (ShellProvider cfg) = runStep cfg "validate" Nothing
    package (ShellProvider cfg)  = runStep cfg "package" Nothing
    transfer (ShellProvider cfg) mEnvPath = runStep cfg "transfer" mEnvPath
    activate (ShellProvider cfg) = runStep cfg "activate" Nothing
    rollback (ShellProvider cfg) = runStep cfg "rollback" Nothing

-- | Helper to run the script with a specific step argument
runStep :: ShellConfig -> String -> Maybe FilePath -> IO (Either DeployError ())
runStep cfg step mEnvPath = do
    putStrLn $ "Running " ++ step ++ " script..."
    let args = case mEnvPath of
                 Just path -> [step, path]
                 Nothing   -> [step]
    (code, _, err) <- readProcessWithExitCode (script cfg) args ""
    case code of
        ExitSuccess -> pure $ Right ()
        ExitFailure _ -> pure $ Left $ ValidationError err
