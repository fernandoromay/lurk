module Lurk.Cookie
    ( getCookie
    , setCookie
    , setSimpleCookie
    , deleteCookie
    ) where

import Data.Text (Text)
import Data.Text.Lazy qualified as TL
import Lurk.Core (Action, getCookie, setHeader, deleteCookie, setSimpleCookie)

-- | Set a cookie with Path=/ and SameSite=Lax defaults
setCookie :: Text -> Text -> Action ()
setCookie name value = setHeader "Set-Cookie" (TL.fromStrict $ name <> "=" <> value <> "; Path=/; SameSite=Lax")
