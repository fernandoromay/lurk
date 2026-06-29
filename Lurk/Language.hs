module Lurk.Language
    ( allLanguages
    , fromText
    , toText
    , withLang
    , Text
    , Data
    , langPaths
    ) where

import Data.Data (Data, toConstr)
import Data.Char qualified as C (toLower)
import Data.Text (Text, pack, replace, toLower)
import Data.List (find)
import Data.Maybe (fromMaybe)
import Lurk.View (ViewContext, currentPath)

allLanguages :: (Enum lang, Bounded lang) => [lang]
allLanguages = [minBound..maxBound]

fromText :: (Data lang, Enum lang, Bounded lang) => lang -> Text -> lang
fromText def t = fromMaybe def $ find (\l -> toText l == t') [minBound..maxBound]
    where  t' = replace "_" "-" (toLower t)

toText :: Data lang => lang -> Text
toText = pack . formatLanguage . show . toConstr

formatLanguage :: String -> String
formatLanguage = map (\c -> if c == '_' then '-' else C.toLower c)

langPaths :: (Data lang, Enum lang, Bounded lang, ?ctx :: ViewContext) => [lang -> Text] -> [(Text, Text)]
langPaths = go
  where
    langs = allLanguages
    go [] = [(toText lang, currentPath) | lang <- langs]
    go (fn : rest)
        | any (\lang -> fn lang == currentPath) langs = [(toText lang, fn lang) | lang <- langs]
        | otherwise = go rest

-- | Bind a language value to the implicit @?lang@ parameter.
-- Use in the router to provide @?lang@ to action handlers.
--
-- @
-- get homePath (withLang homeAction)
-- @
withLang :: lang -> ( (?lang :: lang) => action ) -> action
withLang lang action = let ?lang = lang in action
