{-# LANGUAGE OverloadedStrings #-}
module Commands.New
    ( newProject
    ) where

import System.Directory (doesDirectoryExist, listDirectory, createDirectoryIfMissing, doesFileExist, renameFile, copyFile, getCurrentDirectory)
import System.FilePath (takeBaseName, takeFileName, takeDirectory, dropExtension, (</>))
import Control.Monad (filterM, when)
import Data.List (isPrefixOf, isSuffixOf)
import Data.Char (isAlphaNum, isLower, toLower, toUpper)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as TE

import Shared ( scaffoldTemplates, availableScaffoldTypes, promptChoice
              , promptCustomDir, promptProjectName, capitalize, normalizeName )

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

    let cleanPath = dropWhile (== '/')
        templateFiles = filter (\(fp, _) -> templatePrefix `isPrefixOf` cleanPath fp) scaffoldTemplates
        relFiles = map (\(fp, content) -> (drop (length templatePrefix) (cleanPath fp), content)) templateFiles

    let localModules = discoverLocalModulesFromContent relFiles

    pure $ do
        putStrLn $ "Creating " ++ projectName ++ " from " ++ scaffoldType ++ " scaffold..."
        when usePrefix $ putStrLn $ "Prefix: " ++ prefix ++ ".*"

        mapM_ (\(relPath, content) -> do
            let dst = if takeFileName relPath == "env.example"
                    then ".env.example"
                    else takeFileName relPath
            when (takeFileName relPath `elem` rootFiles) $ do
                let finalContent = if usePrefix && takeFileName relPath == "Router.hs"
                        then let t = TE.decodeUtf8 content
                             in TE.encodeUtf8 $ T.replace "\"public\"" ("\"" <> T.pack targetDir <> "/public\"") t
                        else content
                BS.writeFile dst finalContent
            ) relFiles

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

        mapM_ (\(relPath, content) -> do
            let dstPath = if usePrefix
                    then targetDir </> relPath
                    else relPath
            when (takeFileName relPath `notElem` rootFiles) $ do
                createDirectoryIfMissing True (takeDirectory dstPath)
                BS.writeFile dstPath content
            ) relFiles

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

prefixHsFile :: FilePath -> String -> Set.Set T.Text -> IO ()
prefixHsFile filePath prefix localModules = do
    content <- TIO.readFile filePath
    let prefixed = applyModulePrefix prefix localModules content
    TIO.writeFile filePath prefixed

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
