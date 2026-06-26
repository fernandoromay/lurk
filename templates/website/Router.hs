module Router where

import Lurk.Prelude
import Paths
import Controller.Static

router :: LurkApp
router = do
    routeSettings [ SecurityHeaders, TrailingSlashes, ForceSSL, ServeStatic "public" ]

    get homePath homeAction
