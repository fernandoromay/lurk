module Lurk.Request
    ( preferredLanguages
    , resolveLanguage
    , cfCountry
    ) where

import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types (hAcceptLanguage)
import Network.Wai qualified as Wai
import Web.Scotty (request)
import Lurk.App (Action)

-- Extract preferred languages from the 'Accept-Language' header.
preferredLanguages :: Action [Text]
preferredLanguages = do
    req <- request
    let headers = Wai.requestHeaders req
    case lookup hAcceptLanguage headers of
        Nothing -> pure []
        Just val -> pure $ parseAcceptLanguage (TE.decodeUtf8 val)

-- Parse 'Accept-Language' header value into a list of language codes
parseAcceptLanguage :: Text -> [Text]
parseAcceptLanguage = map (T.takeWhile (/= ';') . T.strip) . T.splitOn ","

-- Identify the user's country using the Cloudflare 'CF-IPCountry' header
cfCountry :: Action (Maybe Text)
cfCountry = do
    req <- request
    let headers = Wai.requestHeaders req
    case lookup "CF-IPCountry" headers of
        Nothing -> pure Nothing
        Just val -> pure $ Just (TE.decodeUtf8 val)

-- Find the first supported language that matches the browser's preferences
resolveLanguage :: [Text] -> [Text] -> Maybe Text
resolveLanguage supported preferred =
    listToMaybe [ s | p <- preferred, s <- supported, s == p ]

