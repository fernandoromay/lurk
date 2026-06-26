-- | HTTP security headers middleware.
--
-- @
-- import Lurk.Routes.Security (securityHeaders, securityHeadersWith)
--
-- -- Use defaults
-- routeSettings [ TrailingSlashes, ForceSSL, ServeStatic "public", SecurityHeaders ]
--
-- -- Override or add specific headers
-- routeSettings [ SecurityHeadersWith
--     [ ("Content-Security-Policy", "default-src 'self'") ]
-- ]
-- @
module Lurk.Routes.Security
    ( securityHeaders
    , securityHeadersWith
    ) where

import Data.ByteString qualified as BS
import Network.HTTP.Types (Header, HeaderName)
import Network.Wai (Middleware, mapResponseHeaders, requestMethod)
import System.Environment (lookupEnv)

-- | Apply default security headers to all responses.
-- HSTS is only added in production (LURK_ENV=production).
securityHeaders :: Middleware
securityHeaders app req respond = do
    headers <- defaultSecurityHeaders
    let method = requestMethod req
        -- Only add HSTS on responses to safe methods
        headers' = if method `elem` ["GET", "HEAD"]
            then headers
            else filter (\(k, _) -> k /= hstsHeader) headers
    app req (respond . mapResponseHeaders (++ headers'))

-- | Apply security headers with overrides.
-- Start from defaults, then merge your list:
--
--   * @(name, \"value\")@ — override or add a header
--   * @(name, \"\")@ — remove a default header
securityHeadersWith :: [Header] -> Middleware
securityHeadersWith extra app req respond = do
    defaults <- defaultSecurityHeaders
    let method = requestMethod req
        merged = mergeHeaders defaults extra
        merged' = if method `elem` ["GET", "HEAD"]
            then merged
            else filter (\(k, _) -> k /= hstsHeader) merged
    app req (respond . mapResponseHeaders (++ merged'))

-- | Merge override list onto defaults. Empty value removes the header.
mergeHeaders :: [Header] -> [Header] -> [Header]
mergeHeaders defaults [] = defaults
mergeHeaders defaults ((name, value) : rest)
    | BS.null value = mergeHeaders (filter (\(k, _) -> k /= name) defaults) rest
    | otherwise = mergeHeaders (replaceOrAdd (name, value) defaults) rest

replaceOrAdd :: Header -> [Header] -> [Header]
replaceOrAdd (name, value) [] = [(name, value)]
replaceOrAdd (name, value) ((k, v) : rest)
    | k == name = (name, value) : rest
    | otherwise = (k, v) : replaceOrAdd (name, value) rest

-- | Default security headers.
defaultSecurityHeaders :: IO [Header]
defaultSecurityHeaders = do
    env <- lookupEnv "LURK_ENV"
    let base =
            [ ("X-Content-Type-Options", "nosniff")
            , ("X-Frame-Options", "DENY")
            , ("X-XSS-Protection", "0")
            , ("Referrer-Policy", "strict-origin-when-cross-origin")
            , ("Permissions-Policy", "geolocation=(), camera=(), microphone=()")
            ]
    let hsts = if env == Just "production"
            then [(hstsHeader, "max-age=31536000; includeSubDomains")]
            else []
    pure (base ++ hsts)

hstsHeader :: HeaderName
hstsHeader = "Strict-Transport-Security"
