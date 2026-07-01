module Main where

import Paths qualified as P (domain)
import Lurk.App
import Lurk.Env (loadEnv)
import Router

loadConfig :: IO AppConfig
loadConfig = do
    pure AppConfig
        { port          = 3000
        , domain        = P.domain
        , sessionMaxAge = Nothing
        , sessionIdle   = Nothing
        , minLogLevel   = LevelInfo
        , database      = Nothing
        }

main :: IO ()
main = do
    loadEnv -- Reads .env file in root directory
    -- For a different env file use: loadEnvFile "route/to/file.env"
    cfg <- loadConfig
    runLurk cfg router
