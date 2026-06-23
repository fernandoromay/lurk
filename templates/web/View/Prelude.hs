module View.Prelude
    ( module Lurk.Prelude
    , module Language
    , assetPath
    , render
    ) where

import Lurk.Prelude hiding (render)
import Lurk.Prelude qualified as Lurk
import Language
import Web.Scotty (request)

mkAssetPath "public"

render :: ((?currentPath :: Text, ?params :: [(Text, Text)]) => Html) -> Action ()
render viewHtml = do
    showLogin <- maybe False (/= "") <$> getCookie "rz_show_login"
    csrfToken <- getCsrfTokenFromRequest
    let params =
            [ ("showLogin", if showLogin then "true" else "false")
            , ("csrfToken", csrfToken)
            ]
    Lurk.render viewHtml params

-- | Extract CSRF token from the current request's session
getCsrfTokenFromRequest :: Action Text
getCsrfTokenFromRequest = do
    req <- request
    case getSessionIdFromHeaders req of
        Nothing -> pure ""
        Just sid -> do
            store <- liftIO getStore
            liftIO $ getCsrfToken store sid
