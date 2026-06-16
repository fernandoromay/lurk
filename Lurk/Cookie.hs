module Lurk.Cookie
    ( getCookie
    , setCookie
    , setSimpleCookie
    , deleteCookie
    ) where

import Data.Text (Text)
import Data.Text.Lazy qualified as TL
import Lurk.App (Action)
import Web.Scotty (getCookie, setHeader, deleteCookie)
import qualified Web.Scotty as Scotty

-- | Set a cookie with Path=/ and SameSite=Lax defaults
setCookie :: Text -> Text -> Action ()
setCookie name value = setHeader "Set-Cookie" (TL.fromStrict $ name <> "=" <> value <> "; Path=/; SameSite=Lax")

-- | Set a cookie with no attributes
setSimpleCookie :: Text -> Text -> Action ()
setSimpleCookie = Scotty.setSimpleCookie
