module Lurk.Validate
    ( -- * Validation type
      Validation(..)
      -- * Error type
    , ValidationError(..)
      -- * Rule type
    , Rule
      -- * Field combinators
    , field
    , fieldMaybe
      -- * Validators
    , required
    , isEmail
    , minLength
    , maxLength
    , numeric
    , oneOf
    , atLeast
    , atMost
    , custom
    , matches
      -- * Running validation
    , validate
    , validateIO
    , runRules
      -- * IO validators
    , IOValidator
    , noIO
    , (<.?>)
    , liftPred
      -- * Session helpers
    , setValidationErrors
    , getValidationErrors
    ) where

import Data.Aeson (encode, decode, (.=), (.:), object, Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (typeMismatch)
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Control.Monad.IO.Class (liftIO)
import Control.Concurrent.STM (readTVarIO)
import Data.Map.Strict qualified as Map

import Lurk.Core (Action, redirect)
import Lurk.Form (FormData(..), getParam, getParamDef)
import Lurk.Request (request)
import Lurk.CSRF (getSessionIdFromHeaders)
import Lurk.Session qualified as Session
import Lurk.Session (SessionStore(..))

----------------------------------------------------------------------
-- VALIDATION RESULT
----------------------------------------------------------------------

-- | Validation result that accumulates errors.
data Validation e a = Failure e | Success a
  deriving (Eq, Show, Functor)

instance Semigroup e => Semigroup (Validation e a) where
  Failure e1 <> Failure e2 = Failure (e1 <> e2)
  Failure e  <> _          = Failure e
  _          <> Failure e  = Failure e
  Success a  <> Success _  = Success a

instance Semigroup e => Applicative (Validation e) where
  pure = Success
  Failure e <*> Failure e' = Failure (e <> e')
  Failure e <*> _          = Failure e
  _          <*> Failure e  = Failure e
  Success f  <*> Success a  = Success (f a)

----------------------------------------------------------------------
-- ERROR TYPE
----------------------------------------------------------------------

-- | A field-level validation error.
data ValidationError = ValidationError
  { vErrorField   :: Text
  , vErrorMessage :: Text
  } deriving (Eq, Show)

instance Aeson.ToJSON ValidationError where
    toJSON (ValidationError field msg) =
        object ["field" .= field, "message" .= msg]

instance Aeson.FromJSON ValidationError where
    parseJSON = Aeson.withObject "ValidationError" $ \o ->
        ValidationError <$> o .: "field" <*> o .: "message"

----------------------------------------------------------------------
-- RULE TYPE
----------------------------------------------------------------------

-- | A validation rule applied to FormData.
type Rule = FormData -> Validation [ValidationError] ValidationError

----------------------------------------------------------------------
-- FIELD COMBINATORS
----------------------------------------------------------------------

-- | Extract a field from FormData and apply validators to it.
--   Validators are composed via <> (Semigroup).
--   Errors accumulate from all validators.
field :: Text -> Rule -> Rule
field fieldName validators fd =
    validators (FormData [(fieldName, fieldVal)])
  where
    fieldVal = fromMaybe "" (getParam fieldName fd)

-- | Extract an optional field. If missing, passes Validation with no error.
--   If present, applies the validator.
fieldMaybe :: Text -> (Maybe Text -> Validation [ValidationError] ValidationError) -> Rule
fieldMaybe fieldName validator fd =
    validator (getParam fieldName fd)

----------------------------------------------------------------------
-- VALIDATORS
----------------------------------------------------------------------

-- | Helper to get the field name from a single-field FormData.
fieldNameOf :: FormData -> Text
fieldNameOf (FormData []) = ""
fieldNameOf (FormData ((k, _):_)) = k

-- | Helper to get the field value from a single-field FormData.
fieldValOf :: FormData -> Text
fieldValOf (FormData []) = ""
fieldValOf (FormData ((_, v):_)) = v

-- | Field is required and non-empty.
required :: Text -> Rule
required msg fd
    | not (T.null val) = Success (ValidationError "" "")
    | otherwise        = Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Must be a valid email (basic format check: contains @, has domain).
isEmail :: Text -> Rule
isEmail msg fd
    | T.isInfixOf "@" val && T.length domain > 1 = Success (ValidationError "" "")
    | otherwise = Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd
    domain = snd $ T.breakOnEnd "@" val

-- | Minimum length (inclusive).
minLength :: Int -> Text -> Rule
minLength minLen msg fd
    | T.length val >= minLen = Success (ValidationError "" "")
    | otherwise = Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Maximum length (inclusive).
maxLength :: Int -> Text -> Rule
maxLength maxLen msg fd
    | T.length val <= maxLen = Success (ValidationError "" "")
    | otherwise = Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Must parse as a number (via reads).
numeric :: Text -> Rule
numeric msg fd =
    case reads (T.unpack val) :: [(Double, String)] of
        [(_, "")] -> Success (ValidationError "" "")
        _         -> Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Must be one of the allowed values.
oneOf :: [Text] -> Text -> Rule
oneOf allowed msg fd
    | val `elem` allowed = Success (ValidationError "" "")
    | otherwise = Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Numeric lower bound (inclusive). Field must parse as Ord a.
atLeast :: forall a. (Ord a, Read a) => a -> Text -> Rule
atLeast bound msg fd =
    case reads (T.unpack val) :: [(a, String)] of
        [(parsed, "")] | parsed >= bound -> Success (ValidationError "" "")
        _ -> Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Numeric upper bound (inclusive). Field must parse as Ord a.
atMost :: forall a. (Ord a, Read a) => a -> Text -> Rule
atMost bound msg fd =
    case reads (T.unpack val) :: [(a, String)] of
        [(parsed, "")] | parsed <= bound -> Success (ValidationError "" "")
        _ -> Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Custom predicate on the field value.
custom :: (Text -> Bool) -> Text -> Rule
custom predicate msg fd
    | predicate val = Success (ValidationError "" "")
    | otherwise     = Failure [ValidationError fn msg]
  where
    fn = fieldNameOf fd
    val = fieldValOf fd

-- | Cross-field: two fields must have equal values (e.g. password + confirm).
matches :: Text -> Text -> Text -> Rule
matches fieldA fieldB msg fd
    | valA == valB = Success (ValidationError "" "")
    | otherwise    = Failure [ValidationError fieldA msg]
  where
    valA = getParamDef fieldA "" fd
    valB = getParamDef fieldB "" fd

----------------------------------------------------------------------
-- RUNNING VALIDATION
----------------------------------------------------------------------

-- | Run pure validation on cached form data.
--   On failure: stores errors in session, calls redirect with the given path.
--   On success: returns FormData.
validate :: Rule -> Text -> FormData -> Action FormData
validate rules redirectPath fd = do
    case rules fd of
        Failure errs -> do
            setValidationErrors errs
            redirect (TL.fromStrict redirectPath)
            pure fd  -- unreachable after redirect
        Success _ -> pure fd

-- | Run pure + IO validation.
--   Pure phase accumulates ALL errors.
--   IO phase runs only if pure passes, short-circuits on first error.
--   On failure: stores errors in session, redirects.
--   On success: returns the result of the action.
validateIO :: Rule
           -> IOValidator FormData
           -> Text
           -> FormData
           -> Action FormData
validateIO rules ioValidator redirectPath fd = do
    case rules fd of
        Failure errs -> do
            setValidationErrors errs
            redirect (TL.fromStrict redirectPath)
            pure fd
        Success _ -> do
            ioResult <- liftIO $ ioValidator fd
            case ioResult of
                Left errMsg -> do
                    setValidationErrors [ValidationError "" errMsg]
                    redirect (TL.fromStrict redirectPath)
                    pure fd
                Right fd' -> pure fd'

-- | Run rules without redirect. Returns the Validation result.
--   For cases where you need to handle errors manually.
runRules :: Rule -> FormData -> Validation [ValidationError] FormData
runRules rules fd =
    case rules fd of
        Failure errs -> Failure errs
        Success _    -> Success fd

----------------------------------------------------------------------
-- IO VALIDATORS
----------------------------------------------------------------------

-- | An IO validation check. Short-circuits on first error.
type IOValidator a = a -> IO (Either Text a)

-- | No IO validation (identity).
noIO :: IOValidator a
noIO = pure . Right

-- | Compose IO validators (left-to-right, short-circuit).
(<.?>) :: IOValidator a -> IOValidator a -> IOValidator a
(<.?>) v1 v2 x = do
    result <- v1 x
    case result of
        Left err -> pure (Left err)
        Right x' -> v2 x'

-- | Lift a pure predicate into IO validation.
liftPred :: (a -> Bool) -> Text -> IOValidator a
liftPred predicate err x
    | predicate x = pure (Right x)
    | otherwise   = pure (Left err)

----------------------------------------------------------------------
-- SESSION HELPERS
----------------------------------------------------------------------

-- | Store validation errors in session (JSON-encoded list).
setValidationErrors :: [ValidationError] -> Action ()
setValidationErrors errs = do
    mSid <- currentSessionId
    case mSid of
        Nothing -> pure ()
        Just sid -> do
            store <- Session.getStoreFromVault
            Session.setSessionValue store sid validationKey
                (T.pack $ LBS.unpack $ encode errs)

-- | Read and consume validation errors from session (one-time read, like flash).
getValidationErrors :: Action [ValidationError]
getValidationErrors = do
    mSid <- currentSessionId
    case mSid of
        Nothing -> pure []
        Just sid -> do
            store <- Session.getStoreFromVault
            sess <- liftIO $ readTVarIO (storeSessions store)
            case Map.lookup sid sess of
                Nothing -> pure []
                Just session ->
                    case Session.getSessionValue validationKey session of
                        Nothing -> pure []
                        Just jsonText -> do
                            Session.deleteSessionValue store sid validationKey
                            case decode (LBS.pack $ T.unpack jsonText) of
                                Just errs -> pure errs
                                Nothing   -> pure []

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

validationKey :: Text
validationKey = "validation_errors"

currentSessionId :: Action (Maybe Session.SessionId)
currentSessionId = getSessionIdFromHeaders <$> request
