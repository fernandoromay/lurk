{-# LANGUAGE RecordWildCards #-}
module Lurk.Session
    ( SessionId
    , Session(..)
    , SessionStore(..)
    , newSessionStore
    , getSession
    , getSessionValue
    , setSessionValue
    , deleteSessionValue
    , newSessionId
    , cleanupSessions
    ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM
import Control.Monad.IO.Class (liftIO)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.Word (Word8)
import System.Entropy (getEntropy)
import Web.Scotty (ActionM, getCookie, setHeader, request)
import qualified Web.Scotty as Scotty

type SessionId = Text

data Session = Session
    { sessionId     :: SessionId
    , sessionData   :: Map Text Text
    , sessionExpiry :: UTCTime
    }

data SessionStore = InMemoryStore
    { storeSessions :: TVar (Map SessionId Session)
    , storeTTL      :: Int  -- seconds
    }

-- | Create a new in-memory session store (24-hour TTL)
newSessionStore :: IO SessionStore
newSessionStore = InMemoryStore
    <$> newTVarIO Map.empty
    <*> pure 86400

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

-- | Get session from request cookie, or create a new one
getSession :: SessionStore -> ActionM Session
getSession store = do
    mCookieId <- getCookie "_session_id"
    case mCookieId of
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
newSession :: SessionStore -> ActionM Session
newSession store = do
    now <- liftIO getCurrentTime
    sid <- liftIO newSessionId
    let sess = Session
            { sessionId     = sid
            , sessionData   = Map.empty
            , sessionExpiry = addUTCTime (fromIntegral $ storeTTL store) now
            }
    liftIO $ atomically $ modifyTVar' (storeSessions store) (Map.insert sid sess)
    Scotty.setSimpleCookie "_session_id" sid
    pure sess

-- | Get a value from a session
getSessionValue :: Text -> Session -> Maybe Text
getSessionValue key Session{..} = Map.lookup key sessionData

-- | Set a value in a session
setSessionValue :: SessionStore -> SessionId -> Text -> Text -> ActionM ()
setSessionValue store sid key val = liftIO $ atomically $ do
    sessions <- readTVar (storeSessions store)
    case Map.lookup sid sessions of
        Just sess -> do
            let updated = sess { sessionData = Map.insert key val (sessionData sess) }
            writeTVar (storeSessions store) (Map.insert sid updated sessions)
        Nothing -> pure ()

-- | Delete a value from a session
deleteSessionValue :: SessionStore -> SessionId -> Text -> ActionM ()
deleteSessionValue store sid key = liftIO $ atomically $ do
    sessions <- readTVar (storeSessions store)
    case Map.lookup sid sessions of
        Just sess -> do
            let updated = sess { sessionData = Map.delete key (sessionData sess) }
            writeTVar (storeSessions store) (Map.insert sid updated sessions)
        Nothing -> pure ()

-- | Background thread: remove expired sessions every 5 minutes
cleanupSessions :: SessionStore -> IO ()
cleanupSessions store = void $ forkIO $ forever $ do
    threadDelay (5 * 60 * 1000000)
    now <- getCurrentTime
    atomically $ modifyTVar' (storeSessions store) $
        Map.filter (\sess -> sessionExpiry sess > now)
  where
    void m = m >> pure ()
    forever a = a >> forever a
