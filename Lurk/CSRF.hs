module Lurk.CSRF
    ( CsrfToken
    , newCsrfToken
    , setCsrfToken
    , getCsrfToken
    , validateCsrfToken
    , csrfMiddleware
    , getSessionIdFromHeaders
    , cacheFormBody
    , lookupCachedFormParam
    , getCachedFormParams
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
import Data.Word (Word8)
import Network.HTTP.Types (status403)
import Network.Wai (Middleware, requestMethod, Request(..))
import Network.Wai qualified as Wai
import System.Entropy (getEntropy)
import System.IO.Unsafe (unsafePerformIO)

import Lurk.Session

type CsrfToken = Text

-- | Internal header name used to pass session ID between middleware layers
sessionHeader :: CI.CI BC.ByteString
sessionHeader = CI.mk "X-Lurk-Session-Id"

-- | Global cache for parsed form bodies, keyed by session ID
{-# NOINLINE formBodyCache #-}
formBodyCache :: TVar (Map.Map SessionId [(Text, Text)])
formBodyCache = unsafePerformIO $ newTVarIO Map.empty

-- | Cache the parsed form body for a given session ID
cacheFormBody :: SessionId -> [(Text, Text)] -> IO ()
cacheFormBody sid params = atomically $
    modifyTVar' formBodyCache (Map.insert sid params)

-- | Look up a single form parameter from the cache
lookupCachedFormParam :: Text -> [(Text, Text)] -> Maybe Text
lookupCachedFormParam = lookup

-- | Get all cached form params for a session ID (and remove from cache)
getCachedFormParams :: SessionId -> IO [(Text, Text)]
getCachedFormParams sid = atomically $ do
    cache <- readTVar formBodyCache
    let params = Map.findWithDefault [] sid cache
    writeTVar formBodyCache (Map.delete sid cache)
    pure params

-- | Generate a CSRF token (32 random bytes, hex-encoded)
newCsrfToken :: IO CsrfToken
newCsrfToken = do
    bytes <- getEntropy 32
    pure $ TE.decodeUtf8 $ bytesToHex bytes

bytesToHex :: BS.ByteString -> BS.ByteString
bytesToHex = BS.concatMap (\b -> BC.pack [hexChar (b `div` 16), hexChar (b `mod` 16)])
  where
    hexChar n
        | n < 10    = toEnum (fromIntegral n + 48)   -- '0'..'9'
        | otherwise = toEnum (fromIntegral n + 87)   -- 'a'..'f'

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
-- Caches the parsed form body so handlers can access it after middleware consumes it.
csrfMiddleware :: SessionStore -> Middleware
csrfMiddleware store app req respond = do
    let method = requestMethod req
    if method `elem` ["POST", "PUT", "DELETE", "PATCH"]
        then do
            body <- LBS.toStrict <$> Wai.strictRequestBody req
            let rawParams = parseFormParams body
            let params = map (\(k, v) -> (TE.decodeUtf8 k, urlDecode v)) rawParams
            let mSubmitted = lookup "_token" params
            let mSid = TE.decodeUtf8 <$> lookup sessionHeader (requestHeaders req)
            case (mSid, mSubmitted) of
                (Just sid, Just submitted) -> do
                    -- Cache the parsed form body for handlers
                    cacheFormBody sid params
                    sessions <- readTVarIO (storeSessions store)
                    case Map.lookup sid sessions of
                        Just sess
                            | validateCsrfToken sess submitted ->
                                app req respond
                        _ -> respond $ Wai.responseLBS status403
                            [("Content-Type", "text/plain")]
                            "CSRF token invalid"
                _ -> respond $ Wai.responseLBS status403
                    [("Content-Type", "text/plain")]
                    "CSRF token missing"
        else app req respond

-- | Parse URL-encoded form body into key-value pairs (raw ByteString)
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

-- | URL-decode a ByteString to Text (handles %XX and +)
urlDecode :: BS.ByteString -> Text
urlDecode = TE.decodeUtf8 . urlDecodeBS
  where
    urlDecodeBS :: BS.ByteString -> BS.ByteString
    urlDecodeBS = go
      where
        go bs
            | BS.null bs = bs
            | w == 0x25 && BS.length bs >= 3 =  -- '%'
                let hex = BS.take 2 (BS.drop 1 bs)
                in case hexToInt hex of
                    Just n  -> BS.singleton (fromIntegral n) <> go (BS.drop 3 bs)
                    Nothing -> BS.singleton w <> go (BS.drop 1 bs)
            | w == 0x2B =  -- '+'
                BS.singleton 0x20 <> go (BS.drop 1 bs)
            | otherwise =
                BS.singleton w <> go (BS.drop 1 bs)
          where
            w = BS.head bs

        hexToInt :: BS.ByteString -> Maybe Int
        hexToInt hex
            | BS.length hex /= 2 = Nothing
            | otherwise =
                let d1 = hexDigit (BS.index hex 0)
                    d2 = hexDigit (BS.index hex 1)
                in (\a b -> a * 16 + b) <$> d1 <*> d2

        hexDigit :: Word8 -> Maybe Int
        hexDigit c
            | c >= 48 && c <= 57  = Just (fromIntegral c - 48)
            | c >= 97 && c <= 102 = Just (fromIntegral c - 87)
            | c >= 65 && c <= 70  = Just (fromIntegral c - 55)
            | otherwise = Nothing

-- | Extract session ID from request headers (set by sessionMiddleware)
getSessionIdFromHeaders :: Request -> Maybe SessionId
getSessionIdFromHeaders req = TE.decodeUtf8 <$> lookup sessionHeader (requestHeaders req)
