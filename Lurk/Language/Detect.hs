module Lurk.Language.Detect
    ( detectLanguage
    , parseAcceptLanguage
    , matchLanguage
    , langFromCookie
    , countryLang
    ) where

import Data.Data (Data)
import Data.List (find, sortBy)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types (hAcceptLanguage)
import Network.Wai qualified as Wai
import Lurk.Core (Action, request)
import Lurk.Cookie (getCookie)
import Lurk.Language (allLanguages, toText, fromText)

-- | Detect the user's preferred language.
--
-- Priority: cookie → Accept-Language header → default (first language).
--
-- @
-- lang <- detectLanguage "lang"
-- render $ homeView lang
-- @
detectLanguage :: forall lang. (Data lang, Enum lang, Bounded lang, Eq lang) => Text -> Action lang
detectLanguage cookieName = do
    saved <- getCookie cookieName
    let def = head (allLanguages :: [lang])
    case saved >>= langFromCookie def of
        Just lang | lang `elem` (allLanguages :: [lang]) -> pure lang
        _ -> do
            req <- request
            let headers = Wai.requestHeaders req
            let prefs = case lookup hAcceptLanguage headers of
                    Nothing -> []
                    Just val -> parseAcceptLanguage (TE.decodeUtf8 val)
            pure $ case matchLanguage (map toText (allLanguages :: [lang])) prefs of
                Just t  -> fromText def t
                Nothing -> def

-- | Parse an @Accept-Language@ header value into a list of @(language, quality)@
-- pairs, sorted by quality descending.
--
-- @
-- parseAcceptLanguage "es, en-US;q=0.9, ko;q=0.5"
--   == [("es",1.0), ("en-US",0.9), ("ko",0.5)]
-- @
parseAcceptLanguage :: Text -> [(Text, Double)]
parseAcceptLanguage = sortBy quality . map parseEntry . splitEntries
  where
    splitEntries = filter (not . T.null) . map T.strip . T.splitOn ","
    parseEntry entry =
        let (lang, rest) = T.breakOn ";" entry
            q = case T.stripPrefix "q=" (T.strip . T.drop 1 $ rest) of
                    Nothing  -> 1.0
                    Just val -> parseQuality val
        in (T.strip lang, q)
    parseQuality t = case reads (T.unpack t) of
        [(n, "")] -> max 0.0 (min 1.0 n)
        _         -> 1.0
    quality (_, a) (_, b) = compare b a

-- | Find the first supported language that matches the browser's preferences.
-- Matches against the language tag (before @-@ subtag).
--
-- @
-- matchLanguage ["en", "es", "ko"] [("en-US", 0.9), ("es", 1.0)]
--   == Just "en"
-- @
matchLanguage :: [Text] -> [(Text, Double)] -> Maybe Text
matchLanguage supported = go
  where
    go [] = Nothing
    go ((tag, _):rest)
        | Just lang <- findSupported supported tag = Just lang
        | otherwise = go rest
    findSupported [] _ = Nothing
    findSupported (s:ss) tag
        | s == tag || s == baseTag tag = Just s
        | otherwise = findSupported ss tag
    baseTag = T.takeWhile (/= '-')

-- | Parse a cookie value into a language. Returns 'Nothing' if the value
-- doesn't match any of the available languages.
--
-- @
-- langFromCookie EN "es" == Just ES
-- langFromCookie EN "fr" == Nothing
-- @
langFromCookie :: (Data lang, Enum lang, Bounded lang, Eq lang) => lang -> Text -> Maybe lang
langFromCookie _ t = find (\l -> toText l == normalized) allLanguages
  where
    normalized = T.toLower $ T.replace "_" "-" t

-- | Map a country code to a language using the provided mapping.
-- Falls back to the first available language if no match.
--
-- @
-- countryLang [EN, ES, KO] [("ES", ES), ("KR", KO)] "US" == EN
-- countryLang [EN, ES, KO] [("ES", ES), ("KR", KO)] "ES" == ES
-- @
countryLang :: [lang] -> [(Text, lang)] -> Text -> lang
countryLang available mapping country =
    fromMaybe (head available) $ lookup country mapping
