module Lurk.Form where

import Control.Concurrent.STM (readTVarIO)
import Control.Monad.IO.Class (liftIO)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Data.Time.Format (parseTimeM, defaultTimeLocale)
import System.Exit (ExitCode(..))
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Control.Exception (try, SomeException)
import Web.Scotty (redirect, request)

import Lurk.App (Action, getStore)
import Lurk.Session qualified as Session
import Lurk.Session (SessionStore(..), Session(..))
import Lurk.CSRF (getSessionIdFromHeaders, getCachedFormParams)

-- | Parsed form data extracted from a cached request body.
newtype FormData = FormData { rawParams :: [(Text, Text)] }

-- | A form guard inspects form data and either rejects with an error
--   message or passes the data through. Runs in 'Action' to allow
--   session access and IO operations.
type FormGuard = FormData -> Action (Either Text FormData)

----------------------------------------------------------------------
-- EXTRACTION HELPERS
----------------------------------------------------------------------

-- | Extract a parameter by key. Returns 'Nothing' if missing.
getParam :: Text -> FormData -> Maybe Text
getParam key (FormData params) = lookup key params

-- | Extract a parameter with a default fallback.
getParamDef :: Text -> Text -> FormData -> Text
getParamDef key def fd = fromMaybe def (getParam key fd)

-- | Extract a parameter, redirecting if missing or empty.
requireParam :: Text -> Text -> FormData -> Action Text
requireParam key redirectPath (FormData params) =
    case lookup key params of
        Just v | not (T.null v) -> pure v
        _ -> redirect (TL.fromStrict redirectPath)

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
--   calls the error handler with the failure message. On success,
--   passes the validated 'FormData' to the action handler.
withForm :: [FormGuard] -> (Text -> Action ()) -> (FormData -> Action ()) -> Action ()
withForm guards onError onOk = do
    params <- readCachedParams
    let fd = FormData params
    result <- runGuards guards fd
    case result of
        Left errMsg -> onError errMsg
        Right valid -> onOk valid
  where
    readCachedParams = do
        req <- request
        case getSessionIdFromHeaders req of
            Nothing -> pure []
            Just sid -> liftIO $ getCachedFormParams sid

    runGuards [] fd = pure $ Right fd
    runGuards (g:gs) fd = do
        result <- g fd
        case result of
            Left err -> pure $ Left err
            Right fd' -> runGuards gs fd'

-- | Like 'withForm', but redirects to @\/404\/@ on any guard failure.
withFormDefault :: [FormGuard] -> (FormData -> Action ()) -> Action ()
withFormDefault guards = withForm guards (\_ -> redirect "/404/")

----------------------------------------------------------------------
-- BUILT-IN GUARDS
----------------------------------------------------------------------

-- | Rejects if the honeypot field is non-empty (bot detection).
guardHoneypot :: Text -> Text -> FormGuard
guardHoneypot fieldName redirectPath fd =
    pure $ case getParam fieldName fd of
        Just v | not (T.null v) -> Left redirectPath
        _ -> Right fd

-- | Rejects if the form was submitted faster than @minSeconds@.
--   Reads the form load time from the session (set by 'setFormLoadTime').
guardMinSubmitTime :: Int -> Text -> FormGuard
guardMinSubmitTime minSeconds redirectPath fd = do
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
                                    pure $ if elapsed >= fromIntegral minSeconds
                                        then Right fd
                                        else Left redirectPath
                                _ -> pure $ Right fd
                Nothing -> pure $ Right fd

-- | Rejects if the email domain lacks valid MX records (2-second timeout).
guardMxRecord :: Text -> Text -> FormGuard
guardMxRecord fieldKey redirectPath fd =
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
            Nothing -> pure $ Right fd  -- timeout, allow
            Just (Left _) -> pure $ Right fd
            Just (Right (ExitSuccess, out, _)) ->
                pure $ if null out then Left redirectPath else Right fd
            Just (Right (ExitFailure _, _, _)) -> pure $ Right fd

    emailDomain addr = case T.breakOnEnd "@" addr of
        ("", _)   -> ""
        (_, dom)  -> dom

-- | Rejects if the field exceeds @maxLen@ characters.
guardMaxLength :: Text -> Int -> Text -> FormGuard
guardMaxLength fieldKey maxLen redirectPath fd =
    pure $ case getParam fieldKey fd of
        Nothing -> Right fd
        Just v
            | T.length v > maxLen -> Left redirectPath
            | otherwise -> Right fd

----------------------------------------------------------------------
-- SESSION HELPERS
----------------------------------------------------------------------

-- | Store the current time in the session as @form_load_time@.
--   Call this when rendering a form page so 'guardMinSubmitTime' can check it later.
setFormLoadTime :: Action ()
setFormLoadTime = do
    req <- request
    case getSessionIdFromHeaders req of
        Nothing -> pure ()
        Just sid -> do
            store <- liftIO getStore
            now <- liftIO getCurrentTime
            Session.setSessionValue store sid "form_load_time" (T.pack (show now))
