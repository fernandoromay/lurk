module Language
    ( Language(..)
    , allLanguages
    , fromText
    , toText
    , toName
    , langPaths
    ) where

import Lurk.Language

-- Edit as needed. First language is the default one
data Language = EN | ES
    deriving (Eq, Enum, Bounded, Data)

toName :: Language -> Text
toName EN = "English"
toName ES = "Español"
