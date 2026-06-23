module Controller.Static where

import Language
import View.Prelude
import View.Home
import Locale.Home qualified as Home

homeAction :: (?lang :: Language) => Action ()
homeAction = render $ homeView (Home.getLocale ?lang)
