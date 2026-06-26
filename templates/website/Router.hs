module Router where

import Lurk.Prelude
import Lurk.App
import Paths
import Controller.Static

router :: LurkApp
router = do
    routeSettings [ SecurityHeaders, TrailingSlashes, ForceSSL, ServeStatic "public" ]

    get homePath homeAction
