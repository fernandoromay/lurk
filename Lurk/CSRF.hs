module Lurk.CSRF
    ( CsrfToken
    , newCsrfToken
    , setCsrfToken
    , getCsrfToken
    , validateCsrfToken
    , csrfMiddleware
    ) where

import Control.Concurrent.STM
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as LBS
import Data.CaseInsensitive qualified as CI
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types (status403)
import Network.Wai (Middleware, requestMethod, Request(..))
import Network.Wai qualified as Wai
import System.Entropy (getEntropy)

import Lurk.Session

type CsrfToken = Text

-- | Internal header name used to pass session ID between middleware layers
sessionHeader :: CI.CI BC.ByteString
sessionHeader = CI.mk "X-Lurk-Session-Id"

-- | Generate a CSRF token (32 random bytes, hex-encoded)
newCsrfToken :: IO CsrfToken
newCsrfToken = do
    bytes <- getEntropy 32
    pure $ TE.decodeUtf8 $ bytesToHex bytes

bytesToHex :: BS.ByteString -> BS.ByteString
bytesToHex = BS.concatMap (\b -> let s = show (fromEnum b :: Int)
                                     padded = if length s < 2 then '0' : s else s
                                 in BC.pack $ take 2 padded)

-- | Store CSRF token in session under "csrf_token" key
setCsrfToken :: SessionStore -> SessionId -> CsrfToken -> IO ()
setCsrfToken store sid token = atomically $ do
    sessions <- readTVar (storeSessions store)
    case Map.lookup sid sessions of
        Just sess -> do
            let updated = sess { sessionData = Map.insert "csrf_token" token (sessionData sess) }
            writeTVar (storeSessions store) (Map.insert sid updated sessions)
        Nothing -> pure ()

-- | Get CSRF token from session, generating and storing one if missing
getCsrfToken :: SessionStore -> SessionId -> IO CsrfToken
getCsrfToken store sid = do
    sessions <- readTVarIO (storeSessions store)
    case Map.lookup sid sessions >>= getSessionValue "csrf_token" of
        Just token -> pure token
        Nothing -> do
            token <- newCsrfToken
            setCsrfToken store sid token
            pure token

-- | Validate a submitted token against the session's stored token
validateCsrfToken :: Session -> CsrfToken -> Bool
validateCsrfToken sess submitted =
    case getSessionValue "csrf_token" sess of
        Just stored -> stored == submitted
        Nothing -> False

-- | WAI middleware: auto-validate CSRF on POST/PUT/DELETE.
-- Returns 403 if token is missing or invalid.
-- Session middleware must run first to set the X-Lurk-Session-Id header.
csrfMiddleware :: SessionStore -> Middleware
csrfMiddleware store app req respond = do
    let method = requestMethod req
    if method `elem` ["POST", "PUT", "DELETE", "PATCH"]
        then do
            body <- LBS.toStrict <$> Wai.strictRequestBody req
            let params = parseFormParams body
            let mSubmitted = lookup "_token" params
            let mSid = TE.decodeUtf8 <$> lookup sessionHeader (requestHeaders req)
            case (mSid, mSubmitted) of
                (Just sid, Just submitted) -> do
                    sessions <- readTVarIO (storeSessions store)
                    case Map.lookup sid sessions of
                        Just sess
                            | validateCsrfToken sess (TE.decodeUtf8 submitted) ->
                                app req respond
                        _ -> respond $ Wai.responseLBS status403
                            [("Content-Type", "text/plain")]
                            "CSRF token invalid"
                _ -> respond $ Wai.responseLBS status403
                    [("Content-Type", "text/plain")]
                    "CSRF token missing"
        else app req respond

-- | Parse URL-encoded form body into key-value pairs
parseFormParams :: BS.ByteString -> [(BS.ByteString, BS.ByteString)]
parseFormParams "" = []
parseFormParams body =
    let pairs = BC.split '&' body
    in map parsePair pairs
  where
    parsePair pair =
        let (k, rest) = BC.break (== '=') pair
            v = BS.drop 1 rest
        in (k, v)
