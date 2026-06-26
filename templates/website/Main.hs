module Main where

import Paths qualified as P (domain)
import Lurk.App
import Lurk.Env (loadEnv)
import Router

loadConfig :: IO Config
loadConfig = do
    pure Config
        { port          = 3000
        , domain        = P.domain
        , sessionMaxAge = Nothing
        , sessionIdle   = Nothing
        , minLogLevel   = LevelInfo
        }

main :: IO ()
main = do
    loadEnv -- Reads .env file in root directory
    -- For a different env file use: loadEnvFile "route/to/file.env"
    cfg <- loadConfig
    putStrLn $ "Starting on http://localhost:" ++ show (port cfg)
    runLurk cfg router
