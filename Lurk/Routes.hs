module Lurk.Routes
  ( getRoute,
    postRoute,
    currentPath,
    activeClass,
  )
where

import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.Wai (rawPathInfo)
import Web.Scotty

getRoute :: T.Text -> ActionM () -> ScottyM ()
getRoute path = get (literal $ T.unpack path)

postRoute :: T.Text -> ActionM () -> ScottyM ()
postRoute path = post (literal $ T.unpack path)

currentPath :: ActionM T.Text
currentPath = TE.decodeUtf8 . rawPathInfo <$> request

activeClass :: T.Text -> T.Text -> T.Text
activeClass uri target
  | target `T.isPrefixOf` uri = "active"
  | otherwise = ""
