{-# LANGUAGE ImplicitParams #-}
module Lurk.View
    ( ViewContext(..)
    , ViewCtx
    , render
    , currentPath
    , csrfToken
    , flash
    ) where

import Data.Text (Text)
import Data.Text.Lazy qualified as TL
import Lurk.Core (Action, html)
import Lurk.Html (Html, ToHtml (..), renderHtml, forEach, forEachWithIndex)
import Lurk.CSRF (fetchCsrfToken)
import Lurk.Flash (Flash(..), getFlash)
import Lurk.Request (fetchCurrentPath)

-- | View context: implicit parameters available in views and partials.
data ViewContext = ViewContext
    { vcCurrentPath :: Text
    , vcCsrfToken   :: Text
    , vcFlash       :: Maybe Flash
    }

-- | View context with language.
-- | The @lang@ type variable allows projects to use their own language type.
type ViewCtx lang = (?ctx :: ViewContext, ?lang :: lang)

-- | Renders LURK Html into a Scotty response
-- Provides @?currentPath@, @?params@, and @?csrfToken@ as implicit parameters.
-- @?lang@ comes from the calling controller's scope (via 'withLang'),
-- not from this function — it flows directly to views.
render :: ((?ctx :: ViewContext) => Html) -> Action ()
render viewHtml = do
    uri <- fetchCurrentPath
    token <- fetchCsrfToken
    flash <- getFlash
    let ?ctx = ViewContext
            { vcCurrentPath = uri
            , vcCsrfToken   = token
            , vcFlash       = flash
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
