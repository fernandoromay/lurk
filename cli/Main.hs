{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs, lookupEnv, setEnv)
import System.Process (callProcess, rawSystem, readProcess)
import System.Directory
import System.FilePath
import System.IO (hPutStr, hClose)
import System.IO.Temp (withSystemTempFile)
import Control.Monad (filterM, when, unless)
import Data.List (isSuffixOf, sort, isInfixOf)
import Data.Char (isAsciiUpper)
import System.Info (os)
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Map as Map
import qualified Lurk.Deploy as Deploy
import qualified Lurk.Deploy.SSH as DeploySSH
import qualified Lurk.Deploy.Docker as DeployDocker
import qualified Log
import Data.Aeson (Value(..), Object, fromJSON, parseJSON)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import Data.Aeson.Types (parseMaybe)

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["run"] -> runProject
        ["build"] -> buildProject
        ["deploy"] -> deployProject
        ["deploy", "--init"] -> initDeploy
        ["kill"] -> do
            port <- detectPort
            killPort port
        ["kill", port] -> killPort port
        _ -> putStrLn "Usage: lurk run | lurk build | lurk deploy | lurk deploy --init | lurk kill [port]"

initDeploy :: IO ()
initDeploy = do
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

    
    ghcVer <- init <$> readProcess "ghc" ["--numeric-version"] ""
    cabalVer <- init <$> readProcess "cabal" ["--numeric-version"] ""
    
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

deployProject :: IO ()
deployProject = do
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
                        _ -> putStrLn $ "Provider not supported: " ++ Deploy.provider settings'

runSSHDeployment :: Value -> Maybe String -> IO ()
runSSHDeployment val mEnvContent = do
    case parseMaybe parseJSON val of
        Nothing -> putStrLn "Failed to parse SSH configuration."
        Just sshCfg -> do
            let provider = DeploySSH.SSHProvider sshCfg
            runDeployment provider mEnvContent

runDockerDeployment :: Value -> Maybe String -> IO ()
runDockerDeployment val mEnvContent = do
    case parseMaybe parseJSON val of
        Nothing -> putStrLn "Failed to parse Docker configuration."
        Just dockerCfg -> do
            let provider = DeployDocker.DockerProvider dockerCfg
            runDeployment provider mEnvContent

runDeployment :: Deploy.DeployProvider p => p -> Maybe String -> IO ()
runDeployment p mEnvContent = do
    Log.logInfo "Running deployment pipeline..."
    
    -- Handle temp .env file
    withSystemTempFile ".env" $ \path h -> do
        case mEnvContent of
            Just content -> hPutStr h content >> hClose h
            Nothing -> hClose h
        
        let envPath = if isNothing mEnvContent then Nothing else Just path

        resSetup <- Deploy.setup p
        case resSetup of
            Left err -> Log.logError $ "Setup failed: " ++ show err
            Right _ -> do
                res <- Deploy.validate p
                case res of
                    Left err -> Log.logError $ "Validation failed: " ++ show err
                    Right _ -> do
                        resPackage <- Deploy.package p
                        case resPackage of
                            Left err -> Log.logError $ "Packaging failed: " ++ show err
                            Right binaryPath -> do
                                resTransfer <- Deploy.transfer p binaryPath envPath
                                case resTransfer of
                                    Left err -> Log.logError $ "Transfer failed: " ++ show err
                                    Right _ -> do
                                        resActivate <- Deploy.activate p
                                        case resActivate of
                                            Left err -> do
                                                Log.logError $ "Activation failed: " ++ show err
                                                Log.logInfo "Attempting rollback..."
                                                resRollback <- Deploy.rollback p
                                                case resRollback of
                                                    Left rErr -> Log.logError $ "Rollback failed: " ++ show rErr
                                                    Right _ -> Log.logSuccess "Rollback successful."
                                            Right _ -> Log.logSuccess "Deployment successful!"


killPort :: String -> IO ()
killPort port = do
    putStrLn $ "Killing processes holding port " ++ port ++ "..."
    case os of
        "mingw32" -> do
            output <- readProcess "netstat" ["-ano"] ""
            let matchingLines = filter (portPattern port) (lines output)
                pids = map (last . words) matchingLines
            mapM_ (\pid -> rawSystem "taskkill" ["/F", "/PID", pid]) pids
        "darwin" -> do
            pids <- readProcess "lsof" ["-t", "-i", ":" ++ port] ""
            mapM_ (\pid -> unless (null pid) $ do
                _ <- rawSystem "kill" ["-9", pid]
                pure ()) (lines pids)
        _ -> do
            _ <- rawSystem "fuser" ["-k", port ++ "/tcp"]
            return ()
  where
    portPattern p line = (":" ++ p) `isInfixOf` line

detectPort :: IO String
detectPort = do
    loadDotEnv
    mEnvPort <- lookupEnv "PORT"
    case mEnvPort of
        Just p -> pure p
        Nothing -> do
            exists <- doesFileExist "Config.hs"
            if not exists
                then pure "3000"
                else do
                    content <- TIO.readFile "Config.hs"
                    let linesOfContent = T.lines content
                        findVal = filter (\line -> "defaultPort =" `T.isInfixOf` line) linesOfContent
                    case findVal of
                        (line:_) -> do
                            let val = T.strip $ snd $ T.breakOn "=" line
                            pure $ T.unpack val
                        [] -> pure "3000"

runProject :: IO ()
runProject = do
    loadDotEnv
    updateCabalModules
    putStrLn "Starting LURK dev server..."
    callProcess "cabal" ["run", "--ghc-options=-v0"]

buildProject :: IO ()
buildProject = do
    loadDotEnv
    updateCabalModules
    putStrLn "Building project..."
    callProcess "cabal" ["build", "--ghc-options=-v0"]

-- | Load .env file if it exists, setting env vars only if not already set
loadDotEnv :: IO ()
loadDotEnv = do
    exists <- doesFileExist ".env"
    if not exists then pure () else do
        content <- TIO.readFile ".env"
        mapM_ (processLine . T.strip) $ T.lines content
  where
    processLine line
        | T.null line = pure ()
        | "--" `T.isPrefixOf` line = pure ()
        | otherwise = case T.breakOn "=" line of
            (key, val)
                | T.null key -> pure ()
                | otherwise -> do
                    let k = T.unpack (T.strip key)
                        v = T.unpack (T.strip (T.drop 1 val))
                    existing <- lookupEnv k
                    case existing of
                        Just _ -> pure ()  -- don't override existing env vars
                        Nothing -> setEnv k v

updateCabalModules :: IO ()
updateCabalModules = do
    cabalFiles <- filter (".cabal" `isSuffixOf`) <$> listDirectory "."
    case cabalFiles of
        [] -> putStrLn "Warning: No .cabal file found in current directory."
        (cabalFile:_) -> do
            putStrLn $ "Scanning directory for Haskell modules to update " ++ cabalFile ++ "..."
            modules <- discoverModules
            content <- TIO.readFile cabalFile
            case injectModules content modules of
                Nothing -> putStrLn "Warning: Could not find 'other-modules:' in the cabal file."
                Just newContent -> do
                    TIO.writeFile cabalFile newContent
                    putStrLn "Successfully auto-updated cabal other-modules."

discoverModules :: IO [String]
discoverModules = do
    -- 1. Find all root-level directories that start with a capital letter
    allFiles <- listDirectory "."
    srcDirs <- filterM (\d -> do
        isDir <- doesDirectoryExist d
        let isCap = not (null d) && isAsciiUpper (head d)
        return (isDir && isCap)
        ) allFiles
    
    -- 2. Scan those directories recursively
    subDirModules <- concat <$> mapM scanDir srcDirs
    
    -- 3. Find root-level .hs files (excluding Main.hs)
    rootHsFiles <- filterM (\f -> do
        isFile <- doesFileExist f
        let isHs = ".hs" `isSuffixOf` f
        let isNotMain = takeFileName f /= "Main.hs"
        return (isFile && isHs && isNotMain)
        ) allFiles
    
    let rootMods = map dropExtension rootHsFiles
    
    return $ sort (subDirModules ++ rootMods)

scanDir :: FilePath -> IO [String]
scanDir dir = do
    exists <- doesDirectoryExist dir
    if not exists
        then return []
        else do
            content <- listDirectory dir
            let fullPaths = map (dir </>) content
            files <- filterM doesFileExist fullPaths
            subdirs <- filterM doesDirectoryExist fullPaths
            
            let hsFiles = filter (\f -> ".hs" `isSuffixOf` f && takeFileName f /= "Main.hs") files
            let currentModules = map (pathToModule . dropExtension) hsFiles
            
            subModules <- concat <$> mapM scanDir subdirs
            return (currentModules ++ subModules)

pathToModule :: FilePath -> String
pathToModule path = map replaceSep (normalise path)
  where
    replaceSep c | isPathSeparator c = '.'
                 | otherwise         = c

injectModules :: T.Text -> [String] -> Maybe T.Text
injectModules content modules = do
    let linesOfContent = T.lines content
    let indexedLines = zip [(0::Int)..] linesOfContent
    
    startIndex <- lookupIndex "other-modules:" indexedLines
    
    -- Find where the next field starts (a line containing ':' that is not 'other-modules:')
    let afterStart = drop (startIndex + 1) indexedLines
    
    let isNextField (_, line) = 
            let stripped = T.strip line
            in ":" `T.isInfixOf` stripped && not ("--" `T.isPrefixOf` stripped)
            
    let blockLines = takeWhile (not . isNextField) afterStart
    let endIndex = if null blockLines then startIndex + 1 else fst (last blockLines) + 1
    
    let formattedModules = map (\m -> "                     " <> T.pack m <> ",") modules
    let cleanFormatted = case reverse formattedModules of
            [] -> []
            (x:xs) -> reverse (T.init x : xs) -- Remove last comma
            
    let (before, _) = splitAt (startIndex + 1) linesOfContent
    let (_, after) = splitAt endIndex linesOfContent
    
    return $ T.unlines (before ++ cleanFormatted ++ after)
  where
    lookupIndex query [] = Nothing
    lookupIndex query ((idx, line):xs)
        | query `T.isInfixOf` line && not ("--" `T.isPrefixOf` T.strip line) = Just idx
        | otherwise = lookupIndex query xs
