{-# LANGUAGE DeriveGeneric #-}
module Commands.Deploy.Shell
    ( ShellProvider(..)
    , ShellConfig(..)
    ) where

import Commands.Deploy.Core
import GHC.Generics (Generic)
import Data.Aeson (FromJSON)
import System.Process (readProcessWithExitCode, readProcess, callProcess)
import System.Exit (ExitCode(..))

data ShellConfig = ShellConfig
    { script       :: FilePath
    , service_name :: String
    } deriving (Show, Generic)

instance FromJSON ShellConfig

data ShellProvider = ShellProvider ShellConfig

instance DeployProvider ShellProvider where
    setup (ShellProvider cfg) = runStep cfg "setup" Nothing
    validate (ShellProvider cfg) = runStep cfg "validate" Nothing

    package (ShellProvider cfg) = do
        putStrLn "Packaging project..."
        callProcess "cabal" ["build", "--minimize"]
        out <- readProcess "cabal" ["list-bin", service_name cfg] ""
        pure $ Right (init out)

    transfer (ShellProvider cfg) binaryPath mEnvPath = runStep cfg "transfer" (Just binaryPath)
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
