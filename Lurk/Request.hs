module Lurk.Request
    ( preferredLanguages
    , resolveLanguage
    , clientIp
    , ipChain
    , parseIpChain
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

-- | Find the first supported language that matches the browser's preferences
resolveLanguage :: [Text] -> [Text] -> Maybe Text
resolveLanguage supported preferred =
    listToMaybe [ s | p <- preferred, s <- supported, s == p ]

-- | Parse a comma-separated header value into a list of IPs.
-- Strips whitespace from each entry.
-- @"1.2.3.4, 5.6.7.8"@ → @["1.2.3.4", "5.6.7.8"]@
parseIpChain :: Text -> [Text]
parseIpChain = filter (not . T.null) . map T.strip . T.splitOn ","

-- | Get the full IP chain from the @X-Forwarded-For@ header.
-- The first element is typically the client IP.
ipChain :: Action [Text]
ipChain = do
    req <- request
    let headers = Wai.requestHeaders req
    pure $ case lookup "X-Forwarded-For" headers of
        Just v  -> parseIpChain (TE.decodeUtf8 v)
        Nothing -> []

-- | Resolve client IP from @X-Forwarded-For@ or @X-Real-IP@ headers.
-- Returns the first (leftmost) IP from @X-Forwarded-For@,
-- falling back to @X-Real-IP@.
clientIp :: Action (Maybe Text)
clientIp = do
    chain <- ipChain
    case chain of
        (ip:_) -> pure (Just ip)
        []     -> do
            req <- request
            let headers = Wai.requestHeaders req
            pure $ TE.decodeUtf8 <$> lookup "X-Real-IP" headers

