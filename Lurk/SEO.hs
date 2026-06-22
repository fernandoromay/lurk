{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
module Lurk.SEO
    ( SEO(..)
    , defaultSEO
    , renderSEO
    , renderAlternates
    ) where

import Data.Text (Text)
import Lurk.Html
import Lurk.QQ

data SEO = SEO
    { title           :: Text
    , metaTitle       :: Text
    , metaDescription :: Text
    , robots          :: Maybe Text
    , canonical       :: Maybe Text
    , ogTitle         :: Maybe Text
    , ogDescription   :: Maybe Text
    , ogType          :: Maybe Text
    , ogImage         :: Maybe Text
    , customTags      :: Html
    }

defaultSEO :: SEO
defaultSEO = SEO
    { title = "UX Title. Change this, please!"
    , metaTitle = "Search Title. This should be optimized for search engines"
    , metaDescription = "Search Description. This should be optimized for search engines"

    -- Optional fields
    , robots = Nothing
    , canonical = Nothing
    , ogTitle = Nothing
    , ogDescription = Nothing
    , ogType = Nothing
    , ogImage = Nothing
    , customTags = mempty
    }

renderSEO :: SEO -> Html
renderSEO seo = [lurk|
    <title>{{title seo}}</title>
    <meta name="title" content="{{metaTitle seo}}">
    <meta name="description" content="{{metaDescription seo}}">
    {{
      case (robots seo) of
        Just r -> (lurk|<meta name="robots" content="{{r}}">|)
        _      -> mempty
    }}
    {{case (canonical seo) of
        Just c -> (lurk|<link rel="canonical" href="{{c}}">|)
        _      -> mempty
    }}
    {{case (ogTitle seo) of
        Just t -> (lurk|<meta property="og:title" content="{{t}}">|)
        _      -> mempty
    }}
    {{case (ogDescription seo) of
        Just d -> (lurk|<meta property="og:description" content="{{d}}">|)
        _      -> mempty
    }}
    {{case (ogType seo) of
        Just t -> (lurk|<meta property="og:type" content="{{t}}">|)
        _      -> mempty
    }}
    {{case (ogImage seo) of
        Just i -> (lurk|<meta property="og:image" content="{{i}}">|)
        _      -> mempty
    }}
    {{customTags seo}}
|]

renderAlternates :: Text -> [(Text, Text)] -> Html
renderAlternates _ [] = mempty
renderAlternates _ [_] = mempty
renderAlternates domain paths@((_, defPath):_) = concatHtml $
    [lurk|<link rel="alternate" hreflang="x-default" href="{{domain <> defPath}}">|] :
    [ concatHtml ["\n    ", [lurk|<link rel="alternate" hreflang="{{lang}}" href="{{domain <> path}}">|]] | (lang, path) <- paths ]