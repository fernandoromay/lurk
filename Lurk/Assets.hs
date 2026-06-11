module Lurk.Assets (asset, mkAssetPath) where

import Language.Haskell.TH
import System.Directory (getModificationTime, doesDirectoryExist, listDirectory)
import System.FilePath ((</>), makeRelative)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Control.Exception (catch, SomeException)
import Control.Monad (forM)
import Data.Functor ((<&>))
import qualified Data.Text as T

-- | Single asset macro (kept for backwards compatibility)
asset :: FilePath -> Q Exp
asset path = do
    let fullPath = "public/" ++ path
    mtime <- runIO $ catch (getModificationTime fullPath <&> Just) (\(_ :: SomeException) -> return Nothing)
    let hash = case mtime of
            Just t  -> "?v=" ++ show (round (utcTimeToPOSIXSeconds t) :: Int)
            Nothing -> ""
    [| T.pack ("/" ++ path ++ hash) |]

-- | Recursively gets all files in a directory
getFilesRecursive :: FilePath -> IO [FilePath]
getFilesRecursive topdir = do
    exists <- doesDirectoryExist topdir
    if not exists then return [] else do
        names <- listDirectory topdir
        paths <- forM names $ \name -> do
            let path = topdir </> name
            isDirectory <- doesDirectoryExist path
            if isDirectory
                then getFilesRecursive path
                else return [path]
        return (concat paths)

-- | Generates a pure `assetPath :: Text -> Text` function that pattern matches on
-- all files in the given directory and returns their hashed URL.
mkAssetPath :: FilePath -> Q [Dec]
mkAssetPath dir = do
    paths <- runIO $ catch (getFilesRecursive dir) (\(_::SomeException) -> return [])
    clauses <- mapM (mkClause dir) paths
    
    -- Fallback clause: assetPath other = "/" <> other
    let fallback = clause [varP (mkName "other")] 
                   (normalB [| T.pack "/" <> $(varE (mkName "other")) |]) []
                   
    let sig = sigD (mkName "assetPath") [t| T.Text -> T.Text |]
    let fun = funD (mkName "assetPath") (map return clauses ++ [fallback])
    
    sequence [sig, fun]

mkClause :: FilePath -> FilePath -> Q Clause
mkClause dir fullPath = do
    mtime <- runIO $ getModificationTime fullPath
    let hash = show (round (utcTimeToPOSIXSeconds mtime) :: Int)
    let relPath = makeRelative dir fullPath
    -- Ensure forward slashes for URLs, even if compiled on Windows
    let urlPath = map (\c -> if c == '\\' then '/' else c) relPath
    let url = "/" ++ urlPath ++ "?v=" ++ hash
    
    clause [litP (stringL urlPath)] (normalB [| T.pack url |]) []
