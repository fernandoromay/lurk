module Main where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Lurk.Env
import Paths qualified as P (domain)
import Lurk.Prelude (runLurk)
import Router (router)

data Config = Config
    { port   :: Int
    , domain :: Text
    }

-- You can delete this if you configure PORT in your .env file
defaultPort :: Int
defaultPort = 3003

loadConfig :: IO Config
loadConfig = do
    env <- loadEnv -- Reads .env file in root directory
    -- For a different env file use: loadEnvFile "route/to/file.env"
    pure Config
        { port   = fromMaybe defaultPort (getEnvInt env "PORT")
        , domain = P.domain
        }

main :: IO ()
main = do
    cfg <- loadConfig
    putStrLn $ "Starting on http://localhost:" ++ show (port cfg)
    runLurk (port cfg) router
