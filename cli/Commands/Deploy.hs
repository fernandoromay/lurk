{-# LANGUAGE OverloadedStrings #-}
module Commands.Deploy
    ( deployCommand
    , initCommand
    ) where

import System.Directory (createDirectoryIfMissing)
import System.IO (hPutStr, hClose)
import System.IO.Temp (withSystemTempFile)
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.Map as Map
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import Data.Aeson (Value(..), parseJSON)
import Data.Aeson.Types (parseMaybe)

import qualified Lurk.Deploy as Deploy
import qualified Lurk.Deploy.SSH as DeploySSH
import qualified Lurk.Deploy.Docker as DeployDocker
import qualified Log

import Shared (updateCabalModules, safeReadProcess)

-- | Entry point for lurk deploy
deployCommand :: IO ()
deployCommand = do
    updateCabalModules
    putStrLn "Deploying project..."
    configRes <- Deploy.loadDeployConfig "lurk.yaml"
    case configRes of
        Left err -> putStrLn $ "Configuration error: " ++ show err
        Right cfg -> do
            let settings = Deploy.deploy cfg
            putStrLn $ "Using provider: " ++ Deploy.provider settings

            -- Resolve ${VAR} placeholders in config
            resolvedConfig <- Deploy.resolveEnvVars (Deploy.config settings)
            case resolvedConfig of
                Left missing -> putStrLn $ "Error: Missing environment variables: " ++ unwords missing
                Right resolvedCfg -> do
                    let settings' = settings { Deploy.config = resolvedCfg }

                    -- Generate .env content
                    mEnvContent <- case Deploy.env_vars settings' of
                        Nothing -> pure Nothing
                        Just m -> Just <$> Deploy.generateEnvContent m

                    -- Run deployment
                    case Deploy.provider settings' of
                        "ssh" -> runSSHDeployment resolvedCfg mEnvContent
                        "docker" -> runDockerDeployment resolvedCfg mEnvContent
                        p -> putStrLn $ "Provider not supported: " ++ p

runSSHDeployment :: Value -> Maybe String -> IO ()
runSSHDeployment val mEnvContent =
    case parseMaybe parseJSON val of
        Nothing -> putStrLn "Failed to parse SSH configuration."
        Just sshCfg -> runDeployment (DeploySSH.SSHProvider sshCfg) mEnvContent

runDockerDeployment :: Value -> Maybe String -> IO ()
runDockerDeployment val mEnvContent =
    case parseMaybe parseJSON val of
        Nothing -> putStrLn "Failed to parse Docker configuration."
        Just dockerCfg -> runDeployment (DeployDocker.DockerProvider dockerCfg) mEnvContent

-- | Entry point for lurk deploy --init
initCommand :: IO ()
initCommand = do
    putStrLn "Initializing deployment workflow..."
    createDirectoryIfMissing True ".github/workflows"
    keys <- Deploy.getEnvKeysFromSource
    projectName <- Deploy.getProjectName

    -- Build config with ${VAR} placeholders
    let configObj = KeyMap.fromList
            [ (Key.fromString "host", String "${VPS_IP}")
            , (Key.fromString "user", String "${VPS_USER}")
            , (Key.fromString "path", String (T.pack ("/var/www/" ++ projectName)))
            , (Key.fromString "service_name", String (T.pack projectName))
            , (Key.fromString "activate_cmd", String (T.pack ("sudo systemctl restart " ++ projectName)))
            ]

    -- Load existing or create new config
    configRes <- Deploy.loadDeployConfig "lurk.yaml"
    let cfg = case configRes of
            Right c -> c
                { Deploy.project = projectName
                , Deploy.deploy = (Deploy.deploy c)
                    { Deploy.provider = "ssh"
                    , Deploy.config = Aeson.Object configObj
                    }
                }
            Left _ -> Deploy.DeployConfig
                { Deploy.project = projectName
                , Deploy.build = Aeson.Object KeyMap.empty
                , Deploy.deploy = Deploy.DeploySettings
                    { Deploy.provider = "ssh"
                    , Deploy.config = Aeson.Object configObj
                    , Deploy.env_vars = Nothing
                    }
                }

    -- Sync env vars
    let currentVars = fromMaybe Map.empty $ Deploy.env_vars (Deploy.deploy cfg)
    let updatedVars = Map.fromList [(k, k) | k <- keys] `Map.union` currentVars
    let newCfg = cfg { Deploy.deploy = (Deploy.deploy cfg) { Deploy.env_vars = Just updatedVars } }

    _ <- Deploy.saveDeployConfig "lurk.yaml" newCfg
    putStrLn $ "Generated lurk.yaml (project: " ++ projectName ++ ")"

    ghcVerRes <- safeReadProcess "ghc" ["--numeric-version"]
    cabalVerRes <- safeReadProcess "cabal" ["--numeric-version"]

    case (ghcVerRes, cabalVerRes) of
        (Left err, _) -> putStrLn $ "Error detecting GHC version: " ++ err
        (_, Left err) -> putStrLn $ "Error detecting Cabal version: " ++ err
        (Right ghcVer, Right cabalVer) -> do
            let yaml = generateWorkflowYaml (Map.keys updatedVars) ghcVer cabalVer
            TIO.writeFile ".github/workflows/deploy.yml" (T.pack yaml)
            putStrLn "Generated .github/workflows/deploy.yml"

generateWorkflowYaml :: [String] -> String -> String -> String
generateWorkflowYaml keys ghcVer cabalVer =
    unlines $
        [ "# -----------------------------------------------------------------------------"
        , "# Lurk Framework - Automated Deployment Pipeline"
        , "#"
        , "# This workflow is triggered on every push to 'main'."
        , "#"
        , "# REQUIRED GITHUB SECRETS:"
        , "# - SSH Secrets:  DEPLOY_SSH_KEY, VPS_IP, VPS_USER"
        , "# - Docker Secrets: DOCKER_USERNAME, DOCKER_PASSWORD"
        , "# - App Secrets:  Any keys defined in your .env or .example.env file."
        , "#"
        , "# NOTE: lurk.yaml is committed to Git with ${VAR} placeholders."
        , "# -----------------------------------------------------------------------------"
        , ""
        , "name: Deploy Lurk Project"
        , ""
        , "on:"
        , "  push:"
        , "    branches: [ main ]"
        , ""
        , "jobs:"
        , "  deploy:"
        , "    runs-on: # OS to run on. E.g., ubuntu-24.04, windows-2022, etc."
        , "    steps:"
         , "      - uses: actions/checkout@v4"
         , "        with:"
         , "          submodules: recursive"
         , ""
         , "      # --- Infrastructure Setup ---"
         , "      - uses: haskell-actions/setup@v2"
         , "        with:"
         , "          ghc-version: '" ++ ghcVer ++ "'"
         , "          cabal-version: '" ++ cabalVer ++ "'"
         , ""
         , "      - name: Cache Cabal"
         , "        uses: actions/cache@v4"
         , "        with:"
         , "          path: |"
         , "            ~/.cabal/store"
         , "            dist-newstyle"
         , "          key: ${{ runner.os }}-cabal-${{ hashFiles('**/*.cabal', '**/cabal.project', '**/cabal.project.freeze') }}"
         , "          restore-keys: |"
         , "            ${{ runner.os }}-cabal-"
         , ""
         , "      # --- Build the Lurk CLI and Binary ---"
         , "      - name: Build"
         , "        run: cabal build lurk"
         , ""
         , "      # --- Secrets Injection & Deployment ---"
         , "      - name: Deploy"
         , "        env:"
         , "          # --- App Secrets ---"
         ] ++ map (\k -> "          " ++ k ++ ": ${{ secrets." ++ k ++ " }}") keys ++
        [ "          # --- SSH Secrets ---"
        , "          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}"
        , "          VPS_IP: ${{ secrets.VPS_IP }}"
        , "          VPS_USER: ${{ secrets.VPS_USER }}"
        , "        run: |"
        , "          # Initialize SSH Agent for secure transfer"
        , "          eval \"$(ssh-agent -s)\""
        , "          echo \"$DEPLOY_SSH_KEY\" | tr -d '\\r' | ssh-add -"
        , "          mkdir -p ~/.ssh"
        , "          ssh-keyscan -H $VPS_IP >> ~/.ssh/known_hosts"
        , ""
        , "          # Execute Lurk Deployment"
        , "          cabal run lurk -- deploy"
        ]

-- | Run the full deployment pipeline with flat error handling
runDeployment :: Deploy.DeployProvider p => p -> Maybe String -> IO ()
runDeployment p mEnvContent = withSystemTempFile ".env" $ \path h -> do
    case mEnvContent of
        Just content -> hPutStr h content >> hClose h
        Nothing -> hClose h
    let envPath = if isNothing mEnvContent then Nothing else Just path
    Log.logInfo "Running deployment pipeline..."
    result <- runPipeline p envPath
    case result of
        Left err -> Log.logError $ show err
        Right () -> Log.logSuccess "Deployment successful!"

-- | Execute pipeline steps sequentially, aborting on first failure
runPipeline :: Deploy.DeployProvider p => p -> Maybe FilePath -> IO (Either Deploy.DeployError ())
runPipeline p envPath = do
    stepResult <- Deploy.setup p
    case stepResult of
        Left err -> pure $ Left err
        Right _ -> do
            stepResult' <- Deploy.validate p
            case stepResult' of
                Left err -> pure $ Left err
                Right _ -> do
                    stepResult'' <- Deploy.package p
                    case stepResult'' of
                        Left err -> pure $ Left err
                        Right binaryPath -> do
                            stepResult''' <- Deploy.transfer p binaryPath envPath
                            case stepResult''' of
                                Left err -> pure $ Left err
                                Right _ -> do
                                    stepResult'''' <- Deploy.activate p
                                    case stepResult'''' of
                                        Left err -> do
                                            Log.logError $ "Activation failed: " ++ show err
                                            Log.logInfo "Attempting rollback..."
                                            rollbackResult <- Deploy.rollback p
                                            case rollbackResult of
                                                Left rErr -> pure $ Left rErr
                                                Right _ -> do
                                                    Log.logSuccess "Rollback successful."
                                                    pure $ Left err
                                        Right _ -> pure $ Right ()
