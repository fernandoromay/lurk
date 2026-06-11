module Lurk.Routes
    ( getRoute
    , postRoute
    ) where

import Web.Scotty
import qualified Data.Text as T

getRoute :: T.Text -> ActionM () -> ScottyM ()
getRoute path = get (literal $ T.unpack path)

postRoute :: T.Text -> ActionM () -> ScottyM ()
postRoute path = post (literal $ T.unpack path)
