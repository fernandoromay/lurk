module Lurk.Form where

import Control.Concurrent.STM (readTVarIO)
import Control.Monad.IO.Class (liftIO)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Data.Time.Format (parseTimeM, defaultTimeLocale)
import System.Exit (ExitCode(..))
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Control.Exception (try, SomeException)
import Lurk.Request (request)

import Lurk.Core (Action)
import Lurk.App (getStore)
import Lurk.Session qualified as Session
import Lurk.Session (SessionStore(..), Session(..))
import Lurk.CSRF (getSessionIdFromHeaders, getCachedFormParams)

-- | Parsed form data extracted from a cached request body.
newtype FormData = FormData { rawParams :: [(Text, Text)] }

-- | A form guard inspects form data and either rejects (running the
--   fallback action) or passes the data through. Runs in 'Action' to
--   allow session access and IO operations.
type FormGuard = FormData -> Action (Either () FormData)

----------------------------------------------------------------------
-- EXTRACTION HELPERS
----------------------------------------------------------------------

-- | Extract a parameter by key. Returns 'Nothing' if missing.
getParam :: Text -> FormData -> Maybe Text
getParam key (FormData params) = lookup key params

-- | Extract a parameter with a default fallback.
getParamDef :: Text -> Text -> FormData -> Text
getParamDef key def fd = fromMaybe def (getParam key fd)

-- | Safely parse a typed value from form data.
parseParam :: Read a => Text -> FormData -> Maybe a
parseParam key fd = do
    val <- getParam key fd
    case reads (T.unpack val) of
        [(x, "")] -> Just x
        _         -> Nothing

----------------------------------------------------------------------
-- FORM RUNNER
----------------------------------------------------------------------

-- | Run a pipeline of guards on cached form data. On the first failure,
--   the guard's fallback action has already executed and short-circuited
--   (e.g. via 'redirect'). On success, returns the validated 'FormData'.
validateForm :: [FormGuard] -> Action FormData
validateForm guards = do
    params <- readCachedParams
    let fd = FormData params
    runGuards guards fd
  where
    readCachedParams = do
        req <- request
        case getSessionIdFromHeaders req of
            Nothing -> pure []
            Just sid -> liftIO $ getCachedFormParams sid

    runGuards [] fd = pure fd
    runGuards (g:gs) fd = do
        result <- g fd
        case result of
            Left ()  -> pure fd   -- unreachable: fallback called redirect
            Right fd' -> runGuards gs fd'

----------------------------------------------------------------------
-- BUILT-IN GUARDS
----------------------------------------------------------------------

-- | Rejects if the honeypot field is non-empty (bot detection).
honeypot :: Text -> Action () -> FormGuard
honeypot fieldName onFail fd =
    case getParam fieldName fd of
        Just v | not (T.null v) -> onFail >> pure (Left ())
        _ -> pure (Right fd)

-- | Rejects if the form was submitted faster than @minSeconds@.
--   Reads the form load time from the session (set by 'setFormLoadTime').
minSubmitTime :: Int -> Action () -> FormGuard
minSubmitTime minSeconds onFail fd = do
    req <- request
    case getSessionIdFromHeaders req of
        Nothing -> pure $ Right fd
        Just sid -> do
            store <- liftIO getStore
            sessions <- liftIO $ readTVarIO (storeSessions store)
            case Map.lookup sid sessions of
                Just sess ->
                    case Session.getSessionValue "form_load_time" sess of
                        Nothing -> pure $ Right fd
                        Just loadTimeText ->
                            case parseTimeM True defaultTimeLocale "%Y-%m-%d %H:%M:%S%Q UTC" (T.unpack loadTimeText) :: Maybe UTCTime of
                                Just loadTime -> do
                                    now <- liftIO getCurrentTime
                                    let elapsed = realToFrac (diffUTCTime now loadTime) :: Double
                                    if elapsed >= fromIntegral minSeconds
                                        then pure $ Right fd
                                        else onFail >> pure (Left ())
                                _ -> pure $ Right fd
                Nothing -> pure $ Right fd

-- | Rejects if the email domain lacks valid MX records (2-second timeout).
mxRecord :: Text -> Action () -> FormGuard
mxRecord fieldKey onFail fd =
    case getParam fieldKey fd of
        Nothing -> pure $ Right fd
        Just email ->
            let domain = emailDomain email
            in if T.null domain
                then pure $ Right fd
                else checkMx domain
  where
    checkMx domain = do
        result <- liftIO $ timeout 2000000 $ try @SomeException $
            readProcessWithExitCode "host" ["-t", "MX", T.unpack domain] ""
        case result of
            Nothing -> pure $ Right fd
            Just (Left _) -> pure $ Right fd
            Just (Right (ExitSuccess, out, _)) ->
                if null out then onFail >> pure (Left ()) else pure $ Right fd
            Just (Right (ExitFailure _, _, _)) -> pure $ Right fd

    emailDomain addr = case T.breakOnEnd "@" addr of
        ("", _)   -> ""
        (_, dom)  -> dom

-- | Rejects if the field exceeds @maxLen@ characters.
maxLength :: Text -> Int -> Action () -> FormGuard
maxLength fieldKey maxLen onFail fd =
    case getParam fieldKey fd of
        Nothing -> pure $ Right fd
        Just v
            | T.length v > maxLen -> onFail >> pure (Left ())
            | otherwise -> pure $ Right fd

-- | Rejects if the field is missing or empty.
requireParam :: Text -> Action () -> FormGuard
requireParam key onFail fd =
    case getParam key fd of
        Just v | not (T.null v) -> pure $ Right fd
        _ -> onFail >> pure (Left ())

----------------------------------------------------------------------
-- SESSION HELPERS
----------------------------------------------------------------------

-- | Store the current time in the session as @form_load_time@.
--   Call this when rendering a form page so 'minSubmitTime' can check it later.
setFormLoadTime :: Action ()
setFormLoadTime = do
    req <- request
    case getSessionIdFromHeaders req of
        Nothing -> pure ()
        Just sid -> do
            store <- liftIO getStore
            now <- liftIO getCurrentTime
            Session.setSessionValue store sid "form_load_time" (T.pack (show now))
