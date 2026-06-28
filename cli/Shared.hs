{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Shared
    ( updateCabalModules
    , scaffoldTemplates
    , availableScaffoldTypes
    , promptChoice
    , promptCustomDir
    , promptProjectName
    , capitalize
    , normalizeName
    , isHsFile
    , isHsModuleFile
    , cleanLeadingSlash
    , filterTemplates
    , resolveTargetDir
    , isImportLine
    , splitAtImports
    , safeReadProcess
    , safeCallProcess
    , parseLanguageConstructors
    , scanControllers
    , scanActions
    , injectImport
    ) where

import System.Directory (doesFileExist, doesDirectoryExist, listDirectory)
import System.FilePath (isPathSeparator, normalise, takeFileName, dropExtension, (</>))
import System.Process (readProcess, callProcess)
import System.IO.Error (tryIOError, isDoesNotExistError)
import Control.Monad (filterM, unless)
import Data.Char (isAsciiUpper, isAlpha, isAlphaNum, toLower, toUpper)
import Data.List (isPrefixOf, isSuffixOf, sort, dropWhileEnd)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.FileEmbed (embedDir, makeRelativeToProject)
import Data.ByteString (ByteString)

-- | All scaffold templates embedded at compile time
scaffoldTemplates :: [(FilePath, ByteString)]
scaffoldTemplates = $(makeRelativeToProject "templates" >>= embedDir)

-- | Available scaffold types from embedded templates
availableScaffoldTypes :: [String]
availableScaffoldTypes =
    let dirs = map (cleanLeadingSlash . fst) scaffoldTemplates
        topDirs = Set.toList $ Set.fromList
            [ takeWhile (/= '/') dir
            | dir <- dirs
            , '/' `elem` dir
            ]
    in topDirs

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

-- | Capitalize first letter
capitalize :: String -> String
capitalize "" = ""
capitalize (c:cs) = toUpper c : cs

-- | Normalize project name: lowercase, spaces to hyphens, trim trailing hyphens
normalizeName :: String -> String
normalizeName = reverse . dropWhile (== '-') . reverse . map toLower . map (\c -> if c == ' ' then '-' else c) . filter (\c -> isAlpha c || c == ' ' || c == '-')

-- File predicates
isHsFile :: FilePath -> Bool
isHsFile f = ".hs" `isSuffixOf` f

isHsModuleFile :: FilePath -> Bool
isHsModuleFile f = isHsFile f && takeFileName f /= "Main.hs"

-- Path helpers
cleanLeadingSlash :: FilePath -> FilePath
cleanLeadingSlash = dropWhile (== '/')

-- Template helpers
filterTemplates :: String -> [(FilePath, ByteString)] -> [(FilePath, ByteString)]
filterTemplates prefix = filter (\(fp, _) -> prefix `isPrefixOf` cleanLeadingSlash fp)

-- Interactive helpers
resolveTargetDir :: String -> IO String
resolveTargetDir question = do
    target <- promptChoice question
        [ ("Root directory (.)", ".")
        , ("Web/ subdirectory", "Web")
        , ("Custom directory", "")
        ]
    case target of
        "." -> pure "."
        "" -> promptCustomDir
        custom -> pure custom

-- Haskell source helpers
isImportLine :: T.Text -> Bool
isImportLine l = "import " `T.isPrefixOf` T.strip l

splitAtImports :: [T.Text] -> ([T.Text], [T.Text], [T.Text])
splitAtImports ls =
    let (before, rest) = span (not . isImportLine) ls
        (imports, after) = span isImportLine rest
    in (before, imports, after)

-- Safe process execution
safeReadProcess :: String -> [String] -> IO (Either String String)
safeReadProcess cmd args = do
    result <- tryIOError $ readProcess cmd args ""
    case result of
        Left e | isDoesNotExistError e -> pure $ Left $ "Required tool not found: " ++ cmd
               | otherwise -> pure $ Left $ "Command failed: " ++ cmd ++ " (" ++ show e ++ ")"
        Right output -> pure $ Right $ dropWhileEnd (== '\n') output

safeCallProcess :: String -> [String] -> IO (Either String ())
safeCallProcess cmd args = do
    result <- tryIOError $ callProcess cmd args
    case result of
        Left e | isDoesNotExistError e -> pure $ Left $ "Required tool not found: " ++ cmd
               | otherwise -> pure $ Left $ "Command failed: " ++ cmd ++ " (" ++ show e ++ ")"
        Right () -> pure $ Right ()

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
    allFiles <- listDirectory "."
    srcDirs <- filterM (\d -> do
        isDir <- doesDirectoryExist d
        let isCap = not (null d) && isAsciiUpper (head d)
        return (isDir && isCap)
        ) allFiles

    subDirModules <- concat <$> mapM scanDir srcDirs

    rootHsFiles <- filterM (\f -> do
        isFile <- doesFileExist f
        return (isFile && isHsModuleFile f)
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

            let hsFiles = filter isHsModuleFile files
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

    let afterStart = drop (startIndex + 1) indexedLines

    let isNextField (_, line) =
            let stripped = T.strip line
            in ":" `T.isInfixOf` stripped && not ("--" `T.isPrefixOf` stripped)

    let blockLines = takeWhile (not . isNextField) afterStart
    let endIndex = if null blockLines then startIndex + 1 else fst (last blockLines) + 1

    let formattedModules = map (\m -> "                     " <> T.pack m <> ",") modules
    let cleanFormatted = case reverse formattedModules of
            [] -> []
            (x:xs) -> reverse (T.init x : xs)

    let (before, _) = splitAt (startIndex + 1) linesOfContent
    let (_, after) = splitAt endIndex linesOfContent

    return $ T.unlines (before ++ cleanFormatted ++ after)
  where
    lookupIndex _ [] = Nothing
    lookupIndex query ((idx, line):xs)
        | query `T.isInfixOf` line && not ("--" `T.isPrefixOf` T.strip line) = Just idx
        | otherwise = lookupIndex query xs

-- | Parse Language.hs to extract language constructors (e.g., ["EN", "ES", "KO"])
parseLanguageConstructors :: FilePath -> IO [String]
parseLanguageConstructors langFile = do
    exists <- doesFileExist langFile
    if not exists then pure [] else do
        content <- TIO.readFile langFile
        let isLangDef line = "data Language" `T.isPrefixOf` T.strip line
                          || "data Language =" `T.isInfixOf` line
        let langLines = dropWhile (not . isLangDef) (T.lines content)
        let langBlock = takeWhile (\l -> not (T.null (T.strip l))
                            && not ("deriving" `T.isInfixOf` l)) langLines
        let combined = T.concat langBlock
        let afterEq = T.drop 1 $ snd $ T.breakOn "=" combined
        let stripped = T.filter (\c -> isAlphaNum c || c == '|') afterEq
        let parsedLangs = map T.unpack $ T.splitOn "|" stripped
        pure (filter (not . null) parsedLangs)

-- | Scan Controller/ directory for .hs files
scanControllers :: FilePath -> IO [String]
scanControllers targetDir = do
    let ctrlDir = targetDir </> "Controller"
    exists <- doesDirectoryExist ctrlDir
    if not exists then pure []
    else filter (".hs" `isSuffixOf`) <$> listDirectory ctrlDir

-- | Scan a controller file for Action () signatures
scanActions :: FilePath -> IO [String]
scanActions ctrlPath = do
    content <- TIO.readFile ctrlPath
    let lines' = T.lines content
    pure [ extractActionName l | l <- lines'
         , ":: " `T.isInfixOf` l && "Action ()" `T.isInfixOf` l ]
  where
    extractActionName l = takeWhile (/= ' ') (T.unpack (T.strip l))

-- | Inject an import line after the last import in a file
injectImport :: FilePath -> T.Text -> IO ()
injectImport filePath importLine = do
    content <- TIO.readFile filePath
    let lines' = T.lines content
    let hasImport = any (\l -> importLine `T.isInfixOf` l) lines'
    unless hasImport $ do
        let (before, impsAndAfter) = span (not . isImportLine) lines'
        let (imps, after) = span isImportLine impsAndAfter
        TIO.writeFile filePath (T.unlines (before ++ imps ++ [importLine] ++ after))
