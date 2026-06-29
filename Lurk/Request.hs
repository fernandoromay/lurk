module Lurk.Request
    ( preferredLanguages
    , fetchCurrentPath
    , clientIp
    , ipChain
    , parseIpChain
    , request
    , LurkRequest
    ) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types (hAcceptLanguage)
import Network.Wai qualified as Wai
import Lurk.Core (Action, request, LurkRequest)

-- Extract preferred languages from the 'Accept-Language' header.
-- Returns language codes in header order (no quality parsing).
-- For quality-sorted parsing, use 'Lurk.Language.Detect.parseAcceptLanguage'.
preferredLanguages :: Action [Text]
preferredLanguages = do
    req <- request
    let headers = Wai.requestHeaders req
    case lookup hAcceptLanguage headers of
        Nothing -> pure []
        Just val -> pure $ map (T.takeWhile (/= ';') . T.strip) $ T.splitOn "," (TE.decodeUtf8 val)


-- | Get the current request path (e.g. "/about", "/products/123").
fetchCurrentPath :: Action T.Text
fetchCurrentPath = TE.decodeUtf8 . Wai.rawPathInfo <$> request

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

