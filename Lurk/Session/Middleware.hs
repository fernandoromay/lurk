module Lurk.Session.Middleware
    ( sessionMiddleware
    ) where

import Control.Concurrent.STM
import Data.ByteString.Char8 qualified as BC
import Data.CaseInsensitive qualified as CI
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Network.Wai (Middleware, Request(..))
import Network.Wai qualified as Wai

import Lurk.Session

-- | Internal header name used to pass session ID between middleware layers
sessionHeader :: CI.CI BC.ByteString
sessionHeader = CI.mk "X-Lurk-Session-Id"

-- | WAI middleware that manages sessions.
-- Reads/creates session ID from "_session_id" cookie.
-- Passes session ID downstream via internal header.
sessionMiddleware :: SessionStore -> Middleware
sessionMiddleware store app req respond = do
    let mCookieSid = parseSessionCookie req
    case mCookieSid of
        Just sid -> do
            sessions <- readTVarIO (storeSessions store)
            case Map.lookup sid sessions of
                Just sess -> do
                    now <- getCurrentTime
                    if sessionExpiry sess > now
                        then continueWithSession sid app req respond
                        else newSessionAndContinue store app req respond
                Nothing -> newSessionAndContinue store app req respond
        Nothing -> newSessionAndContinue store app req respond

-- | Parse _session_id from the Cookie header
parseSessionCookie :: Request -> Maybe SessionId
parseSessionCookie req = do
    cookieHeader <- lookup "Cookie" (requestHeaders req)
    let cookies = parseCookiesSimple cookieHeader
    TE.decodeUtf8 <$> lookup "_session_id" cookies

-- | Simple cookie parser: splits on "; "
parseCookiesSimple :: BC.ByteString -> [(BC.ByteString, BC.ByteString)]
parseCookiesSimple "" = []
parseCookiesSimple bs =
    let pairs = splitOn ';' bs
        trimmed = map parsePair pairs
    in [(k, v) | (k, v) <- trimmed, not (BC.null k)]
  where
    parsePair pair =
        let (k, rest) = BC.break (== '=') pair
            v = BC.drop 1 rest  -- drop the '=' separator
        in (BC.dropWhile (== ' ') k, v)
    splitOn _ "" = [""]
    splitOn c s =
        let (chunk, rest) = BC.break (== c) s
        in chunk : if BC.null rest then [] else splitOn c (BC.drop 1 rest)

-- | Continue processing with an existing session
continueWithSession :: SessionId -> Middleware
continueWithSession sid app req respond =
    let req' = req { requestHeaders = (sessionHeader, TE.encodeUtf8 sid) : requestHeaders req }
    in app req' respond

-- | Create a new session and continue processing
newSessionAndContinue :: SessionStore -> Middleware
newSessionAndContinue store app req respond = do
    now <- getCurrentTime
    sid <- newSessionId
    let sess = Session
            { sessionId     = sid
            , sessionData   = Map.empty
            , sessionExpiry = addUTCTime 86400 now
            }
    atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
    persistSession store sess
    let req' = req { requestHeaders = (sessionHeader, TE.encodeUtf8 sid) : requestHeaders req }
    let cookieVal = BC.pack $ T.unpack $ "_session_id=" <> sid <> "; Path=/; SameSite=Lax; HttpOnly"
    let respond' resp = respond $ Wai.mapResponseHeaders (("Set-Cookie", cookieVal) :) resp
    app req' respond'
