module Main where

import Paths qualified as P (domain)
import Lurk.Prelude
import Lurk.Env
import Router

loadConfig :: IO Config
loadConfig = do
    pure Config
        { port          = 3000
        , domain        = P.domain
        , sessionMaxAge = Nothing
        , sessionIdle   = Nothing
        }

main :: IO ()
main = do
    env <- loadEnv -- Reads .env file in root directory
    -- For a different env file use: loadEnvFile "route/to/file.env"
    cfg <- loadConfig
    putStrLn $ "Starting on http://localhost:" ++ show (port cfg)
    runLurk (port cfg) router
