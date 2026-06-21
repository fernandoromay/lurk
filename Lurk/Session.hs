{-# LANGUAGE RecordWildCards #-}
module Lurk.Session
    ( SessionId
    , Session(..)
    , SessionStore(..)
    , newSessionStore
    , newFileSessionStore
    , getSession
    , getSessionValue
    , setSessionValue
    , deleteSessionValue
    , destroySession
    , newSessionId
    , cleanupSessions
    , persistSession
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Concurrent.STM
import Control.Monad (foldM, forever)
import Control.Monad.IO.Class (liftIO)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.CaseInsensitive qualified as CI
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.Word (Word8)
import System.Entropy (getEntropy)
import System.Directory (doesDirectoryExist, createDirectoryIfMissing, doesFileExist, removeFile, renameFile, listDirectory)
import System.FilePath ((</>))
import Text.Read (readMaybe)
import Network.Wai (Request(..))
import Web.Scotty (ActionM, request)

-- | The action monad for request handling (same as Lurk.App.Action).
--   Defined here to avoid circular import with Lurk.App.
type Action a = ActionM a

type SessionId = Text

data Session = Session
    { sessionId     :: SessionId
    , sessionData   :: Map Text Text
    , sessionExpiry :: UTCTime
    }

data SessionStore
    = InMemoryStore
        { storeSessions :: TVar (Map SessionId Session)
        , storeTTL      :: Int
        }
    | FileStore
        { storeSessions :: TVar (Map SessionId Session)
        , storeTTL      :: Int
        , storeDir      :: FilePath
        }

-- | Create a new in-memory session store (24-hour TTL)
newSessionStore :: IO SessionStore
newSessionStore = InMemoryStore
    <$> newTVarIO Map.empty
    <*> pure 86400

-- | Create a file-backed session store (24-hour TTL)
newFileSessionStore :: FilePath -> IO SessionStore
newFileSessionStore dir = do
    createDirectoryIfMissing True dir
    sessions <- loadAllSessions dir
    store <- FileStore
        <$> newTVarIO sessions
        <*> pure 86400
        <*> pure dir
    pure store

-- | Load all session files from disk into a Map
loadAllSessions :: FilePath -> IO (Map SessionId Session)
loadAllSessions dir = do
    exists <- doesDirectoryExist dir
    if not exists then pure Map.empty else do
        files <- listDirectory dir
        let sessionFiles = filter (\f -> not (f `elem` [".", ".."])) files
        now <- getCurrentTime
        foldM (loadOneSession now dir) Map.empty sessionFiles
  where
    loadOneSession now dir acc fileName = do
        let path = dir </> fileName
        isFile <- doesFileExist path
        if not isFile then pure acc else do
            content <- BC.readFile path
            case parseSessionFile now (T.pack fileName) content of
                Just sess
                    | sessionExpiry sess > now -> pure (Map.insert (sessionId sess) sess acc)
                    | otherwise -> do
                        removeFile path  -- clean up expired
                        pure acc
                Nothing -> pure acc

-- | Parse a session file. Format: first line is expiry, rest are key=value
parseSessionFile :: UTCTime -> SessionId -> BS.ByteString -> Maybe Session
parseSessionFile _ sid content =
    case BC.lines content of
        (expiryLine:kvLines) -> do
            let expiryStr = TE.decodeUtf8 (BC.strip expiryLine)
            -- Parse ISO format time: "2024-01-15 10:30:00 UTC"
            expiry <- parseExpiry (T.unpack expiryStr)
            let kvs = mapMaybe parseKV kvLines
            pure Session
                { sessionId     = sid
                , sessionData   = Map.fromList kvs
                , sessionExpiry = expiry
                }
        [] -> Nothing

parseExpiry :: String -> Maybe UTCTime
parseExpiry s = readMaybe s

parseKV :: BS.ByteString -> Maybe (Text, Text)
parseKV line
    | BC.null line = Nothing
    | otherwise =
        let (k, rest) = BC.break (== '=') line
        in if BC.null rest
            then Nothing
            else Just (TE.decodeUtf8 k, TE.decodeUtf8 (BC.drop 1 rest))

-- | Generate a random 24-byte hex-encoded session ID
newSessionId :: IO SessionId
newSessionId = do
    bytes <- getEntropy 24
    pure $ TE.decodeUtf8 $ BS.concatMap toHexByte bytes

toHexByte :: Word8 -> BS.ByteString
toHexByte b = BS.pack [hexChar hi, hexChar lo]
  where
    hi = (b `shiftR` 4) .&. 0x0F
    lo = b .&. 0x0F
    hexChar n
      | n < 10    = 48 + fromIntegral n       -- '0'..'9'
      | otherwise = 87 + fromIntegral n        -- 'a'..'f'

-- | Get session from request. Uses X-Lurk-Session-Id header (set by session middleware).
-- Falls back to creating a new session if header is missing.
getSession :: SessionStore -> Action Session
getSession store = do
    req <- request
    case TE.decodeUtf8 <$> lookup (CI.mk "X-Lurk-Session-Id") (requestHeaders req) of
        Just sid -> do
            sessions <- liftIO $ readTVarIO (storeSessions store)
            case Map.lookup sid sessions of
                Just sess -> do
                    now <- liftIO getCurrentTime
                    if sessionExpiry sess > now
                        then pure sess
                        else newSession store
                Nothing -> newSession store
        Nothing -> newSession store

-- | Create a new session and set the cookie
newSession :: SessionStore -> Action Session
newSession store = do
    now <- liftIO getCurrentTime
    sid <- liftIO newSessionId
    let sess = Session
            { sessionId     = sid
            , sessionData   = Map.empty
            , sessionExpiry = addUTCTime (fromIntegral $ storeTTL store) now
            }
    liftIO $ atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
    pure sess

-- | Get a value from a session
getSessionValue :: Text -> Session -> Maybe Text
getSessionValue key Session{..} = Map.lookup key sessionData

-- | Set a value in a session
setSessionValue :: SessionStore -> SessionId -> Text -> Text -> Action ()
setSessionValue store sid key val = liftIO $ do
    sessions <- atomically $ do
        sessions <- readTVar (storeSessions store)
        case Map.lookup sid sessions of
            Just sess -> do
                let updated = sess { sessionData = Map.insert key val (sessionData sess) }
                writeTVar (storeSessions store) (Map.insert sid updated sessions)
                pure (Just updated)
            Nothing -> pure Nothing
    case sessions of
        Just sess -> persistSession store sess
        Nothing   -> pure ()

-- | Delete a value from a session
deleteSessionValue :: SessionStore -> SessionId -> Text -> Action ()
deleteSessionValue store sid key = liftIO $ do
    sessions <- atomically $ do
        sessions <- readTVar (storeSessions store)
        case Map.lookup sid sessions of
            Just sess -> do
                let updated = sess { sessionData = Map.delete key (sessionData sess) }
                writeTVar (storeSessions store) (Map.insert sid updated sessions)
                pure (Just updated)
            Nothing -> pure Nothing
    case sessions of
        Just sess -> persistSession store sess
        Nothing   -> pure ()

-- | Destroy a session completely: remove from TVar and delete file from disk.
destroySession :: SessionStore -> SessionId -> IO ()
destroySession store sid = do
    atomically $ modifyTVar' (storeSessions store) (Map.delete sid)
    case store of
        FileStore{..} -> do
            let path = storeDir </> T.unpack sid
            exists <- doesFileExist path
            if exists then removeFile path else pure ()
        _ -> pure ()

-- | Persist a session to disk (no-op for InMemoryStore).
--   Refuses to write if the session ID contains non-hex characters (path traversal guard).
persistSession :: SessionStore -> Session -> IO ()
persistSession InMemoryStore{} _ = pure ()
persistSession FileStore{..} Session{..}
    | not (T.all (`elem` ("0123456789abcdef" :: String)) sessionId) = pure ()
    | otherwise = do
        let path = storeDir </> T.unpack sessionId
        let tmpPath = path ++ ".tmp"
        let expiryLine = show sessionExpiry
        let kvLines = map (\(k, v) -> TE.encodeUtf8 k <> "=" <> TE.encodeUtf8 v) $ Map.toList sessionData
        let content = BC.pack expiryLine <> "\n" <> BC.intercalate "\n" kvLines <> "\n"
        BS.writeFile tmpPath content
        renameFile tmpPath path

-- | Background thread: remove expired sessions every 5 minutes.
--   Returns the 'ThreadId' so the caller can 'killThread' on shutdown.
cleanupSessions :: SessionStore -> IO ThreadId
cleanupSessions store = forkIO $ forever $ do
    threadDelay (5 * 60 * 1000000)
    now <- getCurrentTime
    expired <- atomically $ do
        sessions <- readTVar (storeSessions store)
        let expired = Map.filter (\sess -> sessionExpiry sess <= now) sessions
        writeTVar (storeSessions store) (Map.filter (\sess -> sessionExpiry sess > now) sessions)
        pure expired
    -- Remove expired session files from disk
    case store of
        FileStore{..} -> mapM_ (\sid -> removeFile (storeDir </> T.unpack sid)) (Map.keys expired)
        _ -> pure ()
