{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs)
import System.Process (callProcess)
import System.Directory
import System.FilePath
import Data.List (isSuffixOf, sort)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Control.Monad (filterM, when)

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["run"] -> runProject
        ["build"] -> buildProject
        _ -> putStrLn "Usage: lurk run | lurk build"

runProject :: IO ()
runProject = do
    updateCabalModules
    putStrLn "Starting LURK dev server..."
    callProcess "cabal" ["run"]

buildProject :: IO ()
buildProject = do
    updateCabalModules
    putStrLn "Building project..."
    callProcess "cabal" ["build"]

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
    let srcDirs = ["Application", "Config", "Controller", "Locales", "Types", "View"]
    subDirModules <- concat <$> mapM scanDir srcDirs
    
    let rootFiles = ["Routes.hs", "Types.hs"]
    rootExists <- filterM doesFileExist rootFiles
    let rootMods = map dropExtension rootExists
    
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
