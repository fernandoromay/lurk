module Lurk.Language
    ( allLanguages
    , fromText
    , toText
    , Text
    , Data
    ) where

import Data.Data (Data, toConstr)
import Data.Char qualified as C (toLower)
import Data.Text (Text, pack, replace, toLower)
import Data.List (find)
import Data.Maybe (fromMaybe)

allLanguages :: (Enum a, Bounded a) => [a]
allLanguages = [minBound..maxBound]

fromText :: (Data a, Enum a, Bounded a) => a -> Text -> a
fromText def t = fromMaybe def $ find (\l -> toText l == t') [minBound..maxBound]
    where  t' = replace "_" "-" (toLower t)

toText :: Data a => a -> Text
toText = pack . formatLanguage . show . toConstr

formatLanguage :: String -> String
formatLanguage = map (\c -> if c == '_' then '-' else C.toLower c)
