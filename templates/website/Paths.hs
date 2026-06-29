module Paths where

import Lurk.Prelude (ViewContext, Text)
import Language

domain :: Text
domain = "https://domain.com"

homePath :: Language -> Text
homePath EN = "/"
homePath ES = "/es/"

pageAlts :: (?ctx :: ViewContext) => [(Text, Text)]
pageAlts = langPaths [homePath]
