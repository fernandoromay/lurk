{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs)
import System.Process (callProcess)
import System.Directory
import System.FilePath
import Control.Monad (filterM, when)
import Data.List (isPrefixOf, isSuffixOf, isInfixOf)
import Data.Char (isAlphaNum, isLower, toLower, toUpper)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as TE

import Shared ( loadDotEnv, updateCabalModules, scaffoldTemplates
              , availableScaffoldTypes, promptChoice, promptCustomDir
              , promptProjectName, capitalize, normalizeName )
import qualified Commands.Kill as Kill
import qualified Commands.Deploy as DeployCmd

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["run"] -> runProject
        ["build"] -> buildProject
        ["deploy"] -> DeployCmd.deployCommand
        ["deploy", "--init"] -> DeployCmd.initCommand
        ["kill"] -> Kill.killCommand
        ["kill", port] -> Kill.killPort port
        ["new", scaffoldType] -> newProject scaffoldType
        ["add", "page"] -> addPage ""
        ["add", "page", name] -> addPage name
        _ -> putStrLn "Usage: lurk run | lurk build | lurk deploy | lurk deploy --init | lurk kill [port] | lurk new <type> | lurk add page [name]"

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
                name = T.takeWhile (\c -> isAlphaNum c || c == '_' || c == '\'' || c == '.') afterKw
            in [name | not (T.null name) && name /= "Main"]
        | otherwise = []
      where stripped = T.stripStart line

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
