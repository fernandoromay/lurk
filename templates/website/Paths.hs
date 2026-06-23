module Paths where

import Lurk.Prelude (Text)
import Language

domain :: Text
domain = "https://domain.com"

homePath :: Language -> Text
homePath EN = "/"
homePath ES = "/es/"

pageAlts :: (?currentPath :: Text) => [(Text, Text)]
pageAlts = langPaths [homePath]
