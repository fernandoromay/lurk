{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs, lookupEnv, setEnv)
import System.Process (callProcess, rawSystem, readProcess)
import System.Directory
import System.FilePath
import System.IO (hPutStr, hClose)
import System.IO.Temp (withSystemTempFile)
import Control.Monad (filterM, when)
import Data.List (isSuffixOf, sort)
import Data.Char (isAsciiUpper)
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
import Data.Aeson.Types (parseMaybe)

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["run"] -> runProject
        ["build"] -> buildProject
        ["deploy"] -> deployProject
        ["deploy", "--init"] -> initDeploy
        ["kill"] -> killPort "3000"
        ["kill", port] -> killPort port
        _ -> putStrLn "Usage: lurk run | lurk build | lurk deploy | lurk deploy --init | lurk kill [port]"

initDeploy :: IO ()
initDeploy = do
    putStrLn "Initializing deployment workflow..."
    createDirectoryIfMissing True ".github/workflows"
    keys <- Deploy.getEnvKeysFromSource
    
    -- Load or create default config
    configRes <- Deploy.loadDeployConfig "lurk.yaml"
    cfg <- case configRes of
        Left _ -> pure $ Deploy.DeployConfig "my-project" (Aeson.Object KeyMap.empty) (Deploy.DeploySettings "ssh" (Aeson.Object KeyMap.empty) Nothing)
        Right c -> pure c
        
    -- Sync env vars
    let currentVars = fromMaybe Map.empty $ Deploy.env_vars (Deploy.deploy cfg)
    let updatedVars = Map.fromList [(k, k) | k <- keys] `Map.union` currentVars
    let newCfg = cfg { Deploy.deploy = (Deploy.deploy cfg) { Deploy.env_vars = Just updatedVars } }
    
    _ <- Deploy.saveDeployConfig "lurk.yaml" newCfg

    
    ghcVer <- init <$> readProcess "ghc" ["--numeric-version"] ""
    cabalVer <- init <$> readProcess "cabal" ["--numeric-version"] ""
    
    let yaml = generateWorkflowYaml (Map.keys updatedVars) ghcVer cabalVer
    TIO.writeFile ".github/workflows/deploy.yml" (T.pack yaml)
    putStrLn "Generated/Updated .github/workflows/deploy.yml and lurk.yaml"

generateWorkflowYaml :: [String] -> String -> String -> String
generateWorkflowYaml keys ghcVer cabalVer =
    unlines $ 
        [ "# -----------------------------------------------------------------------------"
        , "# Lurk Framework - Automated Deployment Pipeline"
        , "#"
        , "# This workflow is triggered on every push to 'main'."
        , "#"
        , "# WHAT TO MODIFY:"
        , "# 1. Update the 'runs-on' field below to match your runner OS."
        , "# 2. Map the secrets in the 'env' section below."
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
        , ""
        , "      # --- Infrastructure Setup ---"
        , "      - uses: haskell/actions/setup@v2"
        , "        with:"
        , "          ghc-version: '" ++ ghcVer ++ "'"
        , "          cabal-version: '" ++ cabalVer ++ "'"
        , ""
        , "      # --- Build the Lurk CLI and Binary ---"
        , "      - name: Build"
        , "        run: |"
        , "          cabal update"
        , "          cabal build lurk --minimize"
        , ""
        , "      # --- Secrets Injection & Deployment ---"
        , "      - name: Deploy"
        , "        env:"
        , "          # --- PROJECT SPECIFIC: Map your secrets here ---"
        ] ++ map (\k -> "          " ++ k ++ ": ${{ secrets." ++ k ++ " }}") keys ++
        [ ""
        , "          # -----------------------------------------------"
        , "          "
        , "          # Internal deployment key for SSH auth"
        , "          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}"
        , "          VPS_IP: ${{ secrets.VPS_IP }}"
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
            
            -- Generate .env content
            mEnvContent <- case Deploy.env_vars settings of
                Nothing -> pure Nothing
                Just m -> Just <$> Deploy.generateEnvContent m
            
            -- Run deployment
            case Deploy.provider settings of
                "ssh" -> runSSHDeployment (Deploy.config settings) mEnvContent
                "docker" -> runDockerDeployment (Deploy.config settings) mEnvContent
                _ -> putStrLn $ "Provider not supported: " ++ Deploy.provider settings

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
    putStrLn "Running deployment pipeline..."
    
    -- Handle temp .env file
    withSystemTempFile ".env" $ \path h -> do
        case mEnvContent of
            Just content -> hPutStr h content >> hClose h
            Nothing -> hClose h
        
        let envPath = if isNothing mEnvContent then Nothing else Just path

        res <- Deploy.validate p
        case res of
            Left err -> putStrLn $ "Validation failed: " ++ show err
            Right _ -> do
                resPackage <- Deploy.package p
                case resPackage of
                    Left err -> putStrLn $ "Packaging failed: " ++ show err
                    Right _ -> do
                        resTransfer <- Deploy.transfer p envPath
                        case resTransfer of
                            Left err -> putStrLn $ "Transfer failed: " ++ show err
                            Right _ -> do
                                resActivate <- Deploy.activate p
                                case resActivate of
                                    Left err -> do
                                        putStrLn $ "Activation failed: " ++ show err
                                        putStrLn "Attempting rollback..."
                                        resRollback <- Deploy.rollback p
                                        case resRollback of
                                            Left rErr -> putStrLn $ "Rollback failed: " ++ show rErr
                                            Right _ -> putStrLn "Rollback successful."
                                    Right _ -> putStrLn "Deployment successful!"

killPort :: String -> IO ()
killPort port = do
    putStrLn $ "Killing processes holding port " ++ port ++ "..."
    _ <- rawSystem "fuser" ["-k", port ++ "/tcp"]
    return ()

runProject :: IO ()
runProject = do
    loadDotEnv
    updateCabalModules
    putStrLn "Starting LURK dev server..."
    callProcess "cabal" ["run"]

buildProject :: IO ()
buildProject = do
    loadDotEnv
    updateCabalModules
    putStrLn "Building project..."
    callProcess "cabal" ["build"]

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
