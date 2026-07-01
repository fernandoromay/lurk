-- | SQL migration runner.
-- Reads @.sql@ files from a directory, tracks applied migrations in a @schema_migrations@ table.
module Lurk.DB.Migration
    ( Migration(..)
    , migrate
    , rollback
    , migrations
    , ensureMigrationsTable
    ) where

import Data.List (sort, isSuffixOf, isPrefixOf)
import Data.Maybe (mapMaybe)
import Data.Text (pack)
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Database.SQLite.Simple (Only(..))
import System.Directory (listDirectory, doesFileExist)
import System.FilePath (takeFileName, (</>))
import System.IO (hFlush, stdout)
import Lurk.DB.Core (DatabaseProvider(..), Query(..))

-- | A migration record.
data Migration = Migration
  { migrationId   :: Int
  , migrationFile :: FilePath
  , migrationDate :: String
  } deriving (Show, Eq, Ord)

-- | Ensure the schema_migrations table exists.
ensureMigrationsTable :: DatabaseProvider db => db -> IO ()
ensureMigrationsTable db = do
    _ <- execute db
        (Query
            "CREATE TABLE IF NOT EXISTS schema_migrations (\
            \ id INTEGER PRIMARY KEY,\
            \ file TEXT NOT NULL UNIQUE,\
            \ applied_at TEXT NOT NULL\
            \ )")
        ()
    pure ()

-- | Get IDs of already-applied migrations.
getAppliedMigrations :: DatabaseProvider db => db -> IO [Int]
getAppliedMigrations db = do
    rows <- query db (Query "SELECT id FROM schema_migrations ORDER BY id") ()
    pure (map fromOnly rows)

-- | Parse a migration filename. Returns (id, full path) or Nothing.
parseMigrationFile :: FilePath -> Maybe (Int, FilePath)
parseMigrationFile path =
    let name = takeFileName path
    in if all (\c -> c >= '0' && c <= '9') (takeWhile (/= '_') name)
        then let (idStr, rest) = span (/= '_') name
             in case reads idStr of
                  [(id, "")] -> Just (id, path)
                  _          -> Nothing
        else Nothing

-- | List all migration files from a directory, sorted by ID.
listMigrationFiles :: FilePath -> IO [(Int, FilePath)]
listMigrationFiles dir = do
    exists <- doesFileExist dir
    if not exists then pure [] else do
        files <- listDirectory dir
        let sqlFiles = filter (\f -> ".sql" `isSuffixOf` f) files
            parsed = mapMaybe (\f -> parseMigrationFile (dir </> f)) sqlFiles
        pure (sort parsed)

-- | Read a migration file, split into UP and DOWN sections.
readMigration :: FilePath -> IO (String, Maybe String)
readMigration path = do
    content <- readFile path
    let sections = splitSections content
    pure (unlines (fst sections), fmap unlines (snd sections))

-- | Split migration content into (UP, DOWN) sections.
splitSections :: String -> ([String], Maybe [String])
splitSections content = go (lines content) [] False
  where
    go [] acc _ = (reverse acc, Nothing)
    go (l:ls) acc False
        | "@down" `isInfixOf` l = go ls acc True
        | otherwise = go ls (l:acc) False
    go (_:ls) acc True =
        (reverse acc, Just (dropWhile (\x -> null x || all (== ' ') x) ls))

    isInfixOf :: String -> String -> Bool
    isInfixOf _ [] = False
    isInfixOf needle haystack@(_:rest)
        | needle `isPrefixOf` haystack = True
        | otherwise = isInfixOf needle rest

-- | Run all pending migrations in order.
migrate :: DatabaseProvider db => db -> FilePath -> IO ()
migrate db dir = do
    ensureMigrationsTable db
    files <- listMigrationFiles dir
    applied <- getAppliedMigrations db
    let pending = filter (\(id', _) -> id' `notElem` applied) files
    if null pending
        then putStrLn "All migrations applied."
        else do
            putStrLn $ "Running " ++ show (length pending) ++ " pending migration(s)..."
            mapM_ (runMigration db dir) pending
            putStrLn "Migrations complete."

-- | Run a single migration.
runMigration :: DatabaseProvider db => db -> FilePath -> (Int, FilePath) -> IO ()
runMigration db dir (id', file) = do
    let path = dir </> file
    (upSql, _downSql) <- readMigration path
    putStrLn $ "  Applying: " ++ file
    hFlush stdout
    execute db (Query (pack upSql)) ()
    now <- getCurrentTime
    let timestamp = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now
    execute db
        (Query "INSERT INTO schema_migrations (id, file, applied_at) VALUES (?, ?, ?)")
        (id', file, timestamp)
    hFlush stdout

-- | Rollback the last applied migration (if it has a DOWN section).
rollback :: DatabaseProvider db => db -> FilePath -> IO ()
rollback db dir = do
    ensureMigrationsTable db
    rows <- query db (Query "SELECT id, file FROM schema_migrations ORDER BY id DESC LIMIT 1") ()
            :: IO [(Int, String)]
    case rows of
        [] -> putStrLn "No migrations to rollback."
        [(mid, file)] -> do
            let path = dir </> file
            (_upSql, mDownSql) <- readMigration path
            case mDownSql of
                Nothing -> putStrLn $ "  " ++ file ++ " has no @down section, skipping."
                Just downSql -> do
                    putStrLn $ "  Rolling back: " ++ file
                    hFlush stdout
                    execute db (Query (pack downSql)) ()
                    execute db (Query "DELETE FROM schema_migrations WHERE id = ?") (Only (mid :: Int))
                    putStrLn "Rollback complete."
        _ -> pure ()

-- | List all migrations (applied and pending).
migrations :: DatabaseProvider db => db -> FilePath -> IO [Migration]
migrations db dir = do
    ensureMigrationsTable db
    files <- listMigrationFiles dir
    appliedIds <- getAppliedMigrations db
    now <- getCurrentTime
    let timestamp = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now
    pure $ map (\(id', file) ->
        Migration
            { migrationId   = id'
            , migrationFile = file
            , migrationDate = if id' `elem` appliedIds then timestamp else "pending"
            }) files
