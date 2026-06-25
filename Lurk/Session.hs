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
    , isSessionExpired
    , refreshIdleExp
    , newSessionExps
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Concurrent.STM
import Control.Monad (foldM, forever, when)
import Control.Monad.IO.Class (liftIO)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.CaseInsensitive qualified as CI
import Data.Foldable (for_)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Format (formatTime, parseTimeM, defaultTimeLocale)
import Data.Word (Word8)
import System.Entropy (getEntropy)
import System.Directory (doesDirectoryExist, createDirectoryIfMissing, doesFileExist, removeFile, renameFile, listDirectory)
import System.FilePath ((</>))
import Lurk.Core (Action)
import Lurk.Request (request)
import Network.Wai (Request(..))

type SessionId = Text

data Session = Session
    { sessionId          :: SessionId
    , sessionData        :: Map Text Text
    , sessionAbsoluteExp :: Maybe UTCTime  -- Immutable. Set at creation.
    , sessionIdleExp     :: Maybe UTCTime  -- Refreshes on access.
    }

data SessionStore
    = InMemoryStore
        { storeSessions    :: TVar (Map SessionId Session)
        , storeMaxAge      :: Maybe Int
        , storeIdleTimeout :: Maybe Int
        }
    | FileStore
        { storeSessions    :: TVar (Map SessionId Session)
        , storeMaxAge      :: Maybe Int
        , storeIdleTimeout :: Maybe Int
        , storeDir         :: FilePath
        }

-- | Check if a session has expired based on absolute or idle expiry.
isSessionExpired :: UTCTime -> Session -> Bool
isSessionExpired now Session{..} =
    maybe False (<= now) sessionAbsoluteExp
    || maybe False (<= now) sessionIdleExp

-- | Refresh the idle expiry timestamp. No-op if idle timeout is Nothing.
refreshIdleExp :: Maybe Int -> UTCTime -> Session -> Session
refreshIdleExp Nothing _ sess = sess
refreshIdleExp (Just timeout) now sess =
    sess { sessionIdleExp = Just (addUTCTime (fromIntegral timeout) now) }

-- | Compute initial absolute and idle expiry times from config.
newSessionExps :: Maybe Int -> Maybe Int -> UTCTime -> (Maybe UTCTime, Maybe UTCTime)
newSessionExps mMaxAge mIdle now =
    let absExp = case mMaxAge of
            Just age -> Just (addUTCTime (fromIntegral age) now)
            Nothing  -> case mIdle of
                Just idle -> Just (addUTCTime (fromIntegral idle) now)
                Nothing   -> Just (addUTCTime 86400 now)
        idleExp = (`addUTCTime` now) . fromIntegral <$> mIdle
    in (absExp, idleExp)

-- | Create a new in-memory session store
newSessionStore :: Maybe Int -> Maybe Int -> IO SessionStore
newSessionStore mMaxAge mIdle =
    InMemoryStore
        <$> newTVarIO Map.empty
        <*> pure mMaxAge
        <*> pure mIdle

-- | Create a file-backed session store
newFileSessionStore :: Maybe Int -> Maybe Int -> FilePath -> IO SessionStore
newFileSessionStore mMaxAge mIdle dir = do
    createDirectoryIfMissing True dir
    sessions <- loadAllSessions dir
    FileStore
        <$> newTVarIO sessions
        <*> pure mMaxAge
        <*> pure mIdle
        <*> pure dir

-- | Load all session files from disk into a Map
loadAllSessions :: FilePath -> IO (Map SessionId Session)
loadAllSessions dir = do
    exists <- doesDirectoryExist dir
    if not exists then pure Map.empty else do
        files <- listDirectory dir
        let sessionFiles = filter (\f -> f `notElem` [".", ".."]) files
        now <- getCurrentTime
        foldM (loadOneSession now dir) Map.empty sessionFiles
  where
    loadOneSession now dir acc fileName = do
        let path = dir </> fileName
        isFile <- doesFileExist path
        if not isFile then pure acc else do
            content <- BC.readFile path
            case parseSessionFile (T.pack fileName) content of
                Just sess
                    | not (isSessionExpired now sess) -> pure (Map.insert (sessionId sess) sess acc)
                    | otherwise -> do
                        removeFile path  -- clean up expired
                        pure acc
                Nothing -> pure acc

-- | Parse a session file.
-- Format: line 1 = absolute expiry (ISO 8601 or empty), line 2 = idle expiry (ISO 8601 or empty), rest = key=value
parseSessionFile :: SessionId -> BS.ByteString -> Maybe Session
parseSessionFile sid content =
    case BC.lines content of
        (absLine:idleLine:kvLines) -> do
            let absExp  = parseISO8601 (T.unpack $ TE.decodeUtf8 $ BC.strip absLine)
                idleExp = parseISO8601 (T.unpack $ TE.decodeUtf8 $ BC.strip idleLine)
                kvs     = mapMaybe parseKV kvLines
            if isJust absExp || isJust idleExp
                then Just Session
                    { sessionId          = sid
                    , sessionData        = Map.fromList kvs
                    , sessionAbsoluteExp = absExp
                    , sessionIdleExp     = idleExp
                    }
                else Nothing
        _ -> Nothing

parseISO8601 :: String -> Maybe UTCTime
parseISO8601 "" = Nothing
parseISO8601 s  = parseTimeM False defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" s

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
-- Refreshes idle expiry on access when storeIdleTimeout is set.
getSession :: SessionStore -> Action Session
getSession store = do
    req <- request
    case TE.decodeUtf8 <$> lookup (CI.mk "X-Lurk-Session-Id") (requestHeaders req) of
        Just sid -> do
            sessions <- liftIO $ readTVarIO (storeSessions store)
            case Map.lookup sid sessions of
                Just sess -> do
                    now <- liftIO getCurrentTime
                    if isSessionExpired now sess
                        then newSession store
                        else do
                            let refreshed = refreshIdleExp (storeIdleTimeout store) now sess
                            liftIO $ atomically $ modifyTVar' (storeSessions store) (Map.insert sid refreshed)
                            pure refreshed
                Nothing -> newSession store
        Nothing -> newSession store

-- | Create a new session and set the cookie
newSession :: SessionStore -> Action Session
newSession store = do
    now <- liftIO getCurrentTime
    sid <- liftIO newSessionId
    let (absExp, idleExp) = newSessionExps (storeMaxAge store) (storeIdleTimeout store) now
    let sess = Session
            { sessionId          = sid
            , sessionData        = Map.empty
            , sessionAbsoluteExp = absExp
            , sessionIdleExp     = idleExp
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
    for_ sessions (persistSession store)

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
    for_ sessions (persistSession store)

-- | Destroy a session completely: remove from TVar and delete file from disk.
destroySession :: SessionStore -> SessionId -> IO ()
destroySession store sid = do
    atomically $ modifyTVar' (storeSessions store) (Map.delete sid)
    case store of
        FileStore{..} -> do
            let path = storeDir </> T.unpack sid
            exists <- doesFileExist path
            when exists $ removeFile path
        _ -> pure ()

-- | Persist a session to disk (no-op for InMemoryStore).
--   Refuses to write if the session ID contains non-hex characters (path traversal guard).
persistSession :: SessionStore -> Session -> IO ()
persistSession InMemoryStore{} _ = pure ()
persistSession FileStore{..} Session{..}
    | not (T.all (`elem` ("0123456789abcdef" :: String)) sessionId) = pure ()
    | otherwise = do
        let path     = storeDir </> T.unpack sessionId
        let tmpPath  = path ++ ".tmp"
        let fmt      = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"
        let absLine  = maybe "" fmt sessionAbsoluteExp
        let idleLine = maybe "" fmt sessionIdleExp
        let kvLines  = map (\(k, v) -> TE.encodeUtf8 k <> "=" <> TE.encodeUtf8 v) $ Map.toList sessionData
        let content  = BC.pack absLine <> "\n" <> BC.pack idleLine <> "\n"
                    <> BC.intercalate "\n" kvLines <> "\n"
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
        let expired = Map.filter (isSessionExpired now) sessions
        writeTVar (storeSessions store) (Map.filter (not . isSessionExpired now) sessions)
        pure expired
    -- Remove expired session files from disk
    case store of
        FileStore{..} -> mapM_ (\sid -> removeFile (storeDir </> T.unpack sid)) (Map.keys expired)
        _ -> pure ()
