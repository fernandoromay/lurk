{-# LANGUAGE ImplicitParams #-}
module Lurk.View
    ( ViewContext(..)
    , ViewCtx
    , render
    , currentPath
    , csrfToken
    , flash
    , validationErrors
    , fieldErrors
    ) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Lurk.Core (Action, html)
import Lurk.Html (Html, ToHtml (..), renderHtml, forEach, forEachWithIndex)
import Lurk.CSRF (fetchCsrfToken)
import Lurk.Flash (Flash(..), getFlash)
import Lurk.Request (fetchCurrentPath)
import Lurk.Validate (ValidationError(..), getValidationErrors)

-- | View context: implicit parameters available in views and partials.
data ViewContext = ViewContext
    { vcCurrentPath :: Text
    , vcCsrfToken   :: Text
    , vcFlash       :: Maybe Flash
    , vcValidation  :: [ValidationError]
    }

-- | View context with language.
-- | The @lang@ type variable allows projects to use their own language type.
type ViewCtx lang = (?ctx :: ViewContext, ?lang :: lang)

-- | Renders LURK Html into a Scotty response
-- Provides @?currentPath@, @?params@, @?csrfToken@, and @?ctx@ as implicit parameters.
-- @?lang@ comes from the calling controller's scope (via 'withLang'),
-- not from this function — it flows directly to views.
render :: ((?ctx :: ViewContext) => Html) -> Action ()
render viewHtml = do
    uri <- fetchCurrentPath
    token <- fetchCsrfToken
    flsh <- getFlash
    errs <- getValidationErrors
    let ?ctx = ViewContext
            { vcCurrentPath = uri
            , vcCsrfToken   = token
            , vcFlash       = flsh
            , vcValidation  = errs
            }
    html . TL.fromStrict . renderHtml $ viewHtml

-- | Current path (from ViewContext)
currentPath :: (?ctx :: ViewContext) => Text
currentPath = vcCurrentPath ?ctx

-- | CSRF Token (from ViewContext)
csrfToken :: (?ctx :: ViewContext) => Text
csrfToken = vcCsrfToken ?ctx

-- | Flash message (from ViewContext)
flash :: (?ctx :: ViewContext) => Maybe Flash
flash = vcFlash ?ctx

-- | All validation errors from ViewContext.
validationErrors :: (?ctx :: ViewContext) => [ValidationError]
validationErrors = vcValidation ?ctx

-- | Get all error messages for a specific field, concatenated with ". ".
--   Returns empty Text if no errors.
fieldErrors :: (?ctx :: ViewContext) => Text -> Text
fieldErrors fn =
    T.intercalate ". " $
        map vErrorMessage $
            filter ((== fn) . vErrorField) validationErrors
