module Log
    ( logInfo
    , logSuccess
    , logError
    ) where

import System.Console.ANSI

-- | Subtle informational logging
logInfo :: String -> IO ()
logInfo msg = do
    setSGR [SetColor Foreground Dull Blue]
    putStrLn $ "[INFO] " ++ msg
    setSGR [Reset]

-- | Subtle success logging
logSuccess :: String -> IO ()
logSuccess msg = do
    setSGR [SetColor Foreground Dull Green]
    putStrLn $ "[OK] " ++ msg
    setSGR [Reset]

-- | Error logging
logError :: String -> IO ()
logError msg = do
    setSGR [SetColor Foreground Dull Red]
    putStrLn $ "[ERROR] " ++ msg
    setSGR [Reset]
