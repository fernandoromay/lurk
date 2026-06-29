module Lurk.Flash
    ( FlashLevel(..)
    , Flash(..)
    , setFlash
    , getFlash
    , flashSuccess
    , flashError
    , flashWarning
    ) where

import Control.Concurrent.STM (readTVarIO)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Control.Monad.IO.Class (liftIO)
import Lurk.Request (request)

import Lurk.Core (Action)
import Lurk.CSRF (getSessionIdFromHeaders)
import Lurk.Session qualified as Session

-- | Severity level for flash messages.
data FlashLevel = FlashSuccess | FlashError | FlashWarning
    deriving (Eq, Show)

-- | A one-time message stored in the session and consumed on first read.
data Flash = Flash
    { flashLevel   :: FlashLevel
    , flashMessage :: Text
    } deriving (Eq, Show)

----------------------------------------------------------------------
-- INTERNAL HELPERS
----------------------------------------------------------------------

levelToText :: FlashLevel -> Text
levelToText FlashSuccess = "success"
levelToText FlashError   = "error"
levelToText FlashWarning = "warning"

textToLevel :: Text -> Maybe FlashLevel
textToLevel "success" = Just FlashSuccess
textToLevel "error"   = Just FlashError
textToLevel "warning" = Just FlashWarning
textToLevel _         = Nothing

levelKey, messageKey :: Text
levelKey   = "flash_level"
messageKey = "flash_message"

currentSessionId :: Action (Maybe Session.SessionId)
currentSessionId = do getSessionIdFromHeaders <$> request

----------------------------------------------------------------------
-- CORE API
----------------------------------------------------------------------

-- | Set a flash message. Stored in the session until read by 'getFlash'.
setFlash :: FlashLevel -> Text -> Action ()
setFlash level msg = do
    mSid <- currentSessionId
    case mSid of
        Nothing -> pure ()
        Just sid -> do
            store <- Session.getStoreFromVault
            Session.setSessionValue store sid levelKey (levelToText level)
            Session.setSessionValue store sid messageKey msg

-- | Read and consume the flash message. Returns 'Nothing' if no flash is set
--   or on subsequent reads (one-time consumption).
getFlash :: Action (Maybe Flash)
getFlash = do
    mSid <- currentSessionId
    case mSid of
        Nothing -> pure Nothing
        Just sid -> do
            store <- Session.getStoreFromVault
            sess <- liftIO $ readTVarIO (Session.storeSessions store)
            case Map.lookup sid sess of
                Nothing -> pure Nothing
                Just session -> do
                    let mLvl = Session.getSessionValue levelKey session >>= textToLevel
                        mMsg = Session.getSessionValue messageKey session
                    case (mLvl, mMsg) of
                        (Just lvl, Just msg) -> do
                            Session.deleteSessionValue store sid levelKey
                            Session.deleteSessionValue store sid messageKey
                            pure $ Just Flash { flashLevel = lvl, flashMessage = msg }
                        _ -> pure Nothing

----------------------------------------------------------------------
-- CONVENIENCE
----------------------------------------------------------------------

-- | Set a success flash message.
flashSuccess :: Text -> Action ()
flashSuccess = setFlash FlashSuccess

-- | Set an error flash message.
flashError :: Text -> Action ()
flashError = setFlash FlashError

-- | Set a warning flash message.
flashWarning :: Text -> Action ()
flashWarning = setFlash FlashWarning
