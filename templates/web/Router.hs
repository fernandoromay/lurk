module Router where

import Lurk.Prelude
import Paths
import Controller.Static

router :: LurkApp
router = do
    routeSettings [ ServeStatic "public" ]

    get homePath homeAction
