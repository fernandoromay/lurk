{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Shared
    ( loadDotEnv
    , updateCabalModules
    , scaffoldTemplates
    , availableScaffoldTypes
    , promptChoice
    , promptCustomDir
    , promptProjectName
    , capitalize
    , normalizeName
    ) where

import System.Environment (lookupEnv, setEnv)
import System.Directory (doesFileExist, doesDirectoryExist, listDirectory)
import System.FilePath (isPathSeparator, normalise, takeFileName, dropExtension, (</>))
import Control.Monad (filterM)
import Data.Char (isAsciiUpper, isAlpha, toLower, toUpper)
import Data.List (isSuffixOf, sort)
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
capitalize s = toUpper (head s) : tail s

-- | Normalize project name: lowercase, spaces to hyphens, trim trailing hyphens
normalizeName :: String -> String
normalizeName = reverse . dropWhile (== '-') . reverse . map toLower . map (\c -> if c == ' ' then '-' else c) . filter (\c -> isAlpha c || c == ' ' || c == '-')

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
                        Just _ -> pure ()
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
    allFiles <- listDirectory "."
    srcDirs <- filterM (\d -> do
        isDir <- doesDirectoryExist d
        let isCap = not (null d) && isAsciiUpper (head d)
        return (isDir && isCap)
        ) allFiles

    subDirModules <- concat <$> mapM scanDir srcDirs

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
