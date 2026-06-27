{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Main where

import System.Environment (getArgs, lookupEnv, setEnv)
import System.Process (callProcess, rawSystem, readProcess)
import System.Directory
import System.FilePath
import System.IO (hPutStr, hClose)
import System.IO.Temp (withSystemTempFile)
import Control.Monad (filterM, when, unless)
import Data.List (isPrefixOf, isSuffixOf, sort, isInfixOf)
import Data.Char (isAsciiUpper, isAlpha, isAlphaNum, isLower, toLower, toUpper)
import System.Info (os)
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Map as Map
import qualified Lurk.Deploy as Deploy
import qualified Lurk.Deploy.SSH as DeploySSH
import qualified Lurk.Deploy.Docker as DeployDocker
import qualified Log
import Data.FileEmbed (embedDir, makeRelativeToProject)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as TE
import Data.Aeson (Value(..), Object, fromJSON, parseJSON)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import Data.Aeson.Types (parseMaybe)

-- | All scaffold templates embedded at compile time
scaffoldTemplates :: [(FilePath, ByteString)]
scaffoldTemplates = $(makeRelativeToProject "templates" >>= embedDir)

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
        ["new", scaffoldType] -> newProject scaffoldType
        ["add", "page"] -> addPage ""
        ["add", "page", name] -> addPage name
        _ -> putStrLn "Usage: lurk run | lurk build | lurk deploy | lurk deploy --init | lurk kill [port] | lurk new <type> | lurk add page [name]"

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
    callProcess "cabal" ["run", "-v0"]

buildProject :: IO ()
buildProject = do
    loadDotEnv
    updateCabalModules
    putStrLn "Building project..."
    callProcess "cabal" ["build", "-v0"]

-- | Create a new project from a scaffold template
newProject :: String -> IO ()
newProject scaffoldType = do
    let available = availableScaffoldTypes
    if null available
        then putStrLn "Error: No scaffold types available."
        else if scaffoldType `notElem` available
            then putStrLn $ "Error: Unknown scaffold type '" ++ scaffoldType ++ "'.\nAvailable types: " ++ unwords available
            else do
                target <- promptChoice "Where do you want to create the project?"
                    [ ("Root directory (.)", ".")
                    , ("Web/ subdirectory", "Web")
                    , ("Custom directory", "")
                    ]

                targetDir <- case target of
                    "." -> pure "."
                    "" -> promptCustomDir
                    custom -> pure custom

                defaultName <- case targetDir of
                    "." -> takeBaseName <$> getCurrentDirectory
                    d -> pure d
                projectName <- promptProjectName (normalizeName defaultName)

                let usePrefix = targetDir /= "."
                    prefix = if usePrefix then
                                if target == "Web" then "Web"
                                else capitalize targetDir
                             else ""

                scaffold <- buildScaffold scaffoldType targetDir projectName prefix usePrefix

                -- Check target is empty or doesn't exist
                targetExists <- doesDirectoryExist targetDir
                if targetDir == "."
                    then scaffold
                    else if targetExists
                        then do
                            files <- listDirectory targetDir
                            if null files
                                then scaffold
                                else putStrLn $ "Error: Directory '" ++ targetDir ++ "' is not empty."
                        else scaffold

-- | Available scaffold types from embedded templates
availableScaffoldTypes :: [String]
availableScaffoldTypes =
    let cleanPath = dropWhile (== '/')
        dirs = map (cleanPath . fst) scaffoldTemplates
        topDirs = Set.toList $ Set.fromList
            [ head (splitOn '/' dir)
            | dir <- dirs
            , '/' `elem` dir
            ]
    in topDirs
  where
    splitOn _ [] = [""]
    splitOn c s
        | null rest = [taken]
        | otherwise = taken : splitOn c (drop 1 rest)
      where (taken, rest) = break (== c) s

buildScaffold :: String -> String -> String -> String -> Bool -> IO (IO ())
buildScaffold scaffoldType targetDir projectName prefix usePrefix = do
    let templatePrefix = scaffoldType ++ "/"
        rootFiles = ["cabal.project", "project.cabal", "Main.hs", "Router.hs", "env.example"]

    -- Get template files for this scaffold type (strip leading slashes from embedDir)
    let cleanPath = dropWhile (== '/')
        templateFiles = filter (\(fp, _) -> templatePrefix `isPrefixOf` cleanPath fp) scaffoldTemplates
        relFiles = map (\(fp, content) -> (drop (length templatePrefix) (cleanPath fp), content)) templateFiles

    -- Discover local modules from embedded template content
    let localModules = discoverLocalModulesFromContent relFiles

    pure $ do
        putStrLn $ "Creating " ++ projectName ++ " from " ++ scaffoldType ++ " scaffold..."
        when usePrefix $ putStrLn $ "Prefix: " ++ prefix ++ ".*"

        -- Write root files to ./
        mapM_ (\(relPath, content) -> do
            let dst = if takeFileName relPath == "env.example"
                    then ".env.example"
                    else takeFileName relPath
            when (takeFileName relPath `elem` rootFiles) $ do
                -- Fix ServeStatic path when using subdirectory
                let finalContent = if usePrefix && takeFileName relPath == "Router.hs"
                        then let t = TE.decodeUtf8 content
                             in TE.encodeUtf8 $ T.replace "\"public\"" ("\"" <> T.pack targetDir <> "/public\"") t
                        else content
                BS.writeFile dst finalContent
            ) relFiles

        -- Rename project.cabal → {name}.cabal and update name/executable fields
        let srcCabal = "project.cabal"
            dstCabal = projectName ++ ".cabal"
        srcCabalExists <- doesFileExist srcCabal
        when srcCabalExists $ do
            renameFile srcCabal dstCabal
            cabalContent <- TIO.readFile dstCabal
            let updated = T.replace "name:            project" ("name:            " <> T.pack projectName)
                        $ T.replace "executable project" ("executable " <> T.pack projectName)
                        cabalContent
            TIO.writeFile dstCabal updated

        -- Write remaining files
        mapM_ (\(relPath, content) -> do
            let dstPath = if usePrefix
                    then targetDir </> relPath
                    else relPath
            when (takeFileName relPath `notElem` rootFiles) $ do
                createDirectoryIfMissing True (takeDirectory dstPath)
                BS.writeFile dstPath content
            ) relFiles

        -- Prefix Haskell modules if needed
        when usePrefix $ do
            rootHs <- filter (".hs" `isSuffixOf`) <$> listDirectory "."
            mapM_ (\f -> prefixHsFile f prefix localModules) rootHs

            let prefixDir dir = do
                    files <- filter (".hs" `isSuffixOf`) <$> listDirectory dir
                    mapM_ (\f -> prefixHsFile (dir </> f) prefix localModules) files
                    subDirs <- filterM doesDirectoryExist =<< map (dir </>) <$> listDirectory dir
                    mapM_ prefixDir subDirs
            prefixDir targetDir

        putStrLn $ "\nDone! Next steps:"
        putStrLn $ "  lurk run"

promptCustomDir :: IO String
promptCustomDir = do
    putStrLn "Directory name:"
    putStr "> "
    name <- getLine
    let cleaned = filter (\c -> isAlpha c || c == ' ') name
    if null cleaned
        then do
            putStrLn "Error: Name must contain at least one letter."
            promptCustomDir
        else pure (capitalize (filter isAlpha cleaned))

promptProjectName :: String -> IO String
promptProjectName defaultName = do
    putStrLn $ "Project name [" ++ defaultName ++ "]:"
    putStr "> "
    name <- getLine
    let cleaned = normalizeName name
    if null cleaned
        then pure defaultName
        else pure cleaned

-- | Copy a directory recursively, skipping hidden files
copyDir :: FilePath -> FilePath -> IO ()
copyDir src dest = do
    createDirectoryIfMissing True dest
    entries <- listDirectory src
    mapM_ (\entry -> do
        let srcPath = src </> entry
            destPath = dest </> entry
        isDir <- doesDirectoryExist srcPath
        if isDir
            then copyDir srcPath destPath
            else copyFile srcPath destPath
        ) entries

-- | Prefix all module references in a Haskell source file
prefixHsFile :: FilePath -> String -> Set.Set T.Text -> IO ()
prefixHsFile filePath prefix localModules = do
    content <- TIO.readFile filePath
    let prefixed = applyModulePrefix prefix localModules content
    TIO.writeFile filePath prefixed

-- | Apply module prefix to module declarations, import statements,
-- and module references in export lists and hiding clauses
applyModulePrefix :: String -> Set.Set T.Text -> T.Text -> T.Text
applyModulePrefix prefix localModules text = T.intercalate "\n" $ map processLine (T.lines text)
  where
    p = T.pack prefix
    firstComponents = Set.map (T.takeWhile (/= '.')) localModules

    processLine line
        | "module Main " `T.isPrefixOf` stripped = line
        | "module " `T.isPrefixOf` stripped =
            let afterKw = T.drop 7 line
                (name, rest) = T.break (\c -> c == ' ' || c == '(' || c == '\n') afterKw
            in if not (T.null name) && name `Set.member` localModules
               then "module " <> p <> "." <> name <> prefixModuleRefs rest
               else prefixModuleRefs rest
        | "import " `T.isPrefixOf` stripped =
            let afterKw = T.drop 7 line
                (name, rest) = T.break (\c -> c == ' ' || c == '(' || c == '\n' || c == '\r') afterKw
                firstComponent = T.takeWhile (/= '.') name
            in if not (T.null name) && firstComponent `Set.member` firstComponents
               then "import " <> p <> "." <> name <> prefixModuleRefs rest
               else line
        | otherwise = prefixModuleRefs line
      where stripped = T.stripStart line

    -- Replace "module X" references in export lists and hiding clauses
    prefixModuleRefs :: T.Text -> T.Text
    prefixModuleRefs = go
      where
        go txt
          | "module " `T.isPrefixOf` txt =
              let afterKw = T.drop 7 txt
                  (name, rest) = T.break (\c -> c == ' ' || c == ',' || c == ')' || c == '\n') afterKw
                  firstComponent = T.takeWhile (/= '.') name
              in if not (T.null name) && firstComponent `Set.member` firstComponents
                 then "module " <> p <> "." <> name <> go rest
                 else txt
          | T.null txt = txt
          | otherwise =
              let (before, after) = T.breakOn "module " txt
              in before <> go after

-- | Discover all local module names from embedded template content
discoverLocalModulesFromContent :: [(FilePath, ByteString)] -> Set.Set T.Text
discoverLocalModulesFromContent files =
    let hsFiles = filter (\(fp, _) -> ".hs" `isSuffixOf` fp) files
        moduleNames = concatMap (\(_, content) -> extractModuleNames (TE.decodeUtf8 content)) hsFiles
    in Set.fromList moduleNames
  where
    extractModuleNames :: T.Text -> [T.Text]
    extractModuleNames = concatMap extractModuleName . T.lines

    extractModuleName :: T.Text -> [T.Text]
    extractModuleName line
        | "module " `T.isPrefixOf` stripped =
            let afterKw = T.drop 7 line
                name = T.takeWhile (\c -> isAlpha c || c == '_' || c == '\'' || c == '.') afterKw
            in [name | not (T.null name) && name /= "Main"]
        | otherwise = []
      where stripped = T.stripStart line

-- | Capitalize first letter
capitalize :: String -> String
capitalize "" = ""
capitalize s = toUpper (head s) : tail s

-- | Normalize project name: lowercase, spaces to hyphens, trim trailing hyphens
normalizeName :: String -> String
normalizeName = reverse . dropWhile (== '-') . reverse . map toLower . map (\c -> if c == ' ' then '-' else c) . filter (\c -> isAlpha c || c == ' ' || c == '-')

-- | Prompt user to choose from numbered options
promptChoice :: String -> [(String, String)] -> IO String
promptChoice question options = do
    putStrLn question
    mapM_ (\(i, (label, _)) -> putStrLn $ "  " ++ show i ++ ") " ++ label) (zip [1::Int ..] options)
    putStr "> "
    input <- getLine
    case reads input of
        [(n, _)] | n >= 1 && n <= length options -> pure (snd (options !! (n - 1)))
        _ -> do
            putStrLn "Invalid choice."
            promptChoice question options

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

addPage :: String -> IO ()
addPage defaultName = do
    putStrLn "--- Adding New Page ---"
    pageNameInput <- if not (null defaultName)
        then pure defaultName
        else do
            putStrLn "Page Name (e.g., About Us):"
            putStr "> "
            getLine

    let cleanName = filter (\c -> isAlphaNum c || c == ' ' || c == '-') pageNameInput
    let wordsList = words $ map (\c -> if c == '-' then ' ' else c) cleanName
    let pascalName = concatMap capitalize wordsList
    let camelName = case wordsList of
            [] -> ""
            (w:ws) -> map toLower w ++ concatMap capitalize ws
    let kebabName = T.unpack $ T.intercalate "-" $ map (T.toLower . T.pack) wordsList

    target <- promptChoice "Where is the module located?"
        [ ("Root directory (.)", ".")
        , ("Web/ subdirectory", "Web")
        , ("Custom directory", "")
        ]
    targetDir <- case target of
        "." -> pure "."
        "" -> promptCustomDir
        custom -> pure custom

    let ctrlDir = targetDir </> "Controller"
    ctrlExists <- doesDirectoryExist ctrlDir
    ctrlFiles <- if ctrlExists
        then filter (\f -> ".hs" `isSuffixOf` f) <$> listDirectory ctrlDir
        else pure []
    
    targetCtrl <- if null ctrlFiles
        then do
            putStrLn $ "Warning: No controllers found in " ++ ctrlDir
            pure ""
        else do
            choice <- promptChoice "Controller to modify:" (map (\f -> (f, f)) ctrlFiles)
            pure $ ctrlDir </> choice

    let langFile = targetDir </> "Language.hs"
    langExists <- doesFileExist langFile
    langs <- if langExists
        then do
            content <- TIO.readFile langFile
            let isLangDef line = "data Language" `T.isPrefixOf` T.strip line || "data Language =" `T.isInfixOf` line
            let langLines = dropWhile (not . isLangDef) (T.lines content)
            let langBlock = takeWhile (\l -> not (T.null (T.strip l)) && not ("deriving" `T.isInfixOf` l)) langLines
            let combined = T.concat langBlock
            let afterEq = T.drop 1 $ snd $ T.breakOn "=" combined
            let stripped = T.filter (\c -> isAlphaNum c || c == '|') afterEq
            let parsedLangs = map T.unpack $ T.splitOn "|" stripped
            pure (filter (not . null) parsedLangs)
        else pure []

    let templatePrefix = "add/page/"
    let cleanPath = dropWhile (== '/')
    let templateFiles = filter (\(fp, _) -> templatePrefix `isPrefixOf` cleanPath fp) scaffoldTemplates
    
    let mLocaleTemplate = lookup "add/page/Locale.hs" templateFiles
    let mViewTemplate = lookup "add/page/View.hs" templateFiles

    case (mLocaleTemplate, mViewTemplate) of
        (Just localeTpl, Just viewTpl) -> do
            let replacePlaceholders text = 
                    T.replace "{{PascalName}}" (T.pack pascalName) $
                    T.replace "{{camelName}}" (T.pack camelName) $
                    T.replace "{{kebab-name}}" (T.pack kebabName) text
            
            let langImpls = if null langs
                    then "locale = " ++ pascalName ++ "Locale { seo = commonSeo { canonical = Just $ domain <> " ++ camelName ++ "Path }, title = \"\", description = \"\" }"
                    else unlines [ "locale " ++ l ++ " = " ++ pascalName ++ "Locale\n    { seo = commonSeo { canonical = Just $ domain <> " ++ camelName ++ "Path " ++ l ++ " }\n    , title = \"\"\n    , description = \"\"\n    }" | l <- langs ]

            let localeContent = T.replace "{{language-implementations}}" (T.pack langImpls) $ replacePlaceholders (TE.decodeUtf8 localeTpl)
            let viewContent = replacePlaceholders (TE.decodeUtf8 viewTpl)

            createDirectoryIfMissing True (targetDir </> "Locale")
            createDirectoryIfMissing True (targetDir </> "View")
            
            TIO.writeFile (targetDir </> "Locale" </> pascalName ++ ".hs") localeContent
            putStrLn $ "Created " ++ (targetDir </> "Locale" </> pascalName ++ ".hs")
            
            TIO.writeFile (targetDir </> "View" </> pascalName ++ ".hs") viewContent
            putStrLn $ "Created " ++ (targetDir </> "View" </> pascalName ++ ".hs")

            -- Inject into Paths.hs
            let pathsFile = targetDir </> "Paths.hs"
            pathsExists <- doesFileExist pathsFile
            when pathsExists $ do
                pathsContent <- TIO.readFile pathsFile
                let pathsImpls = if null langs
                        then T.pack $ camelName ++ "Path :: Text\n" ++ camelName ++ "Path = \"/" ++ kebabName ++ "/\"\n"
                        else T.pack $ unlines $ (camelName ++ "Path :: Language -> Text") :
                            [ camelName ++ "Path " ++ l ++ " = \"/" ++ (if l == "EN" then "" else T.unpack (T.toLower (T.pack l)) ++ "/") ++ kebabName ++ "/\"" | l <- langs ]
                
                -- find pageAlts
                let pLines = T.lines pathsContent
                let injectPageAlts [] = []
                    injectPageAlts (l:ls)
                        | "pageAlts = langPaths [" `T.isInfixOf` l = 
                            let (before, after) = T.breakOn "]" l
                                prefix = if "[" `T.isSuffixOf` T.strip before then "" else ", "
                            in (before <> prefix <> T.pack camelName <> "Path" <> after) : ls
                        | otherwise = l : injectPageAlts ls
                
                let updatedPaths = T.unlines (injectPageAlts pLines) <> "\n" <> pathsImpls
                TIO.writeFile pathsFile updatedPaths
                putStrLn $ "Updated " ++ pathsFile

            -- Inject into Controller
            when (not (null targetCtrl)) $ do
                ctrlContent <- TIO.readFile targetCtrl
                let cLines = T.lines ctrlContent
                let isImport l = "import " `T.isPrefixOf` T.strip l
                let (beforeImports, rest1) = span (not . isImport) cLines
                let (imports, afterImports) = span isImport rest1
                let newImports = 
                        [ T.pack $ "import View." ++ pascalName
                        , T.pack $ "import Locale." ++ pascalName ++ " qualified as " ++ pascalName
                        ]
                
                let actionImpl = T.pack $ unlines
                        [ ""
                        , camelName ++ "Action :: (?lang :: Language) => Action ()"
                        , camelName ++ "Action = render $ " ++ camelName ++ "View (" ++ pascalName ++ ".locale ?lang)"
                        ]
                
                let updatedCtrl = T.unlines (beforeImports ++ imports ++ newImports ++ afterImports) <> "\n" <> actionImpl
                TIO.writeFile targetCtrl updatedCtrl
                putStrLn $ "Updated " ++ targetCtrl

            -- Inject into Router.hs
            let routerFile = targetDir </> "Router.hs"
            routerExists <- doesFileExist routerFile
            when routerExists $ do
                routerContent <- TIO.readFile routerFile
                let rLines = T.lines routerContent
                
                -- Import controller if needed
                let ctrlModName = dropExtension (takeFileName targetCtrl)
                let hasCtrlImport = any (\l -> ("import Controller." <> T.pack ctrlModName) `T.isInfixOf` l) rLines
                let isImport l = "import " `T.isPrefixOf` T.strip l
                let rLinesWithImport = if hasCtrlImport || null targetCtrl
                        then rLines
                        else let (bi, r1) = span (not . isImport) rLines
                                 (ims, ai) = span isImport r1
                             in bi ++ ims ++ [T.pack $ "import Controller." ++ ctrlModName] ++ ai

                -- Inject route before notFound or at end
                let injectRoute [] = [T.pack $ "    get " ++ camelName ++ "Path " ++ camelName ++ "Action"]
                    injectRoute (l:ls)
                        | "notFound " `T.isInfixOf` l = (T.pack $ "    get " ++ camelName ++ "Path " ++ camelName ++ "Action") : l : ls
                        | otherwise = l : injectRoute ls
                
                TIO.writeFile routerFile (T.unlines (injectRoute rLinesWithImport))
                putStrLn $ "Updated " ++ routerFile
                
            putStrLn "Page scaffolding complete!"
        _ -> putStrLn "Error: Could not find Locale.hs or View.hs templates in add/page/"

