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
    { title             :: Text
    , metaTitle         :: Text
    , metaDescription   :: Text
    , robots            :: Maybe Text
    , canonical         :: Maybe Text
    , ogTitle           :: Maybe Text
    , ogDescription     :: Maybe Text
    , ogType            :: Maybe Text
    , ogImage           :: Maybe Text
    , ogImageAlt        :: Maybe Text
    , ogUrl             :: Maybe Text
    , ogSiteName        :: Maybe Text
    , twitterCard       :: Maybe Text
    , twitterTitle      :: Maybe Text
    , twitterDescription :: Maybe Text
    , twitterImage      :: Maybe Text
    , twitterImageAlt   :: Maybe Text
    , twitterSite       :: Maybe Text
    , twitterCreator    :: Maybe Text
    , customTags        :: Html
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
    , ogImageAlt = Nothing
    , ogUrl = Nothing
    , ogSiteName = Nothing
    , twitterCard = Nothing
    , twitterTitle = Nothing
    , twitterDescription = Nothing
    , twitterImage = Nothing
    , twitterImageAlt = Nothing
    , twitterSite = Nothing
    , twitterCreator = Nothing
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
        _      -> (lurk|<meta property="og:title" content="{{title seo}}">|)
    }}
    {{case (ogDescription seo) of
        Just d -> (lurk|<meta property="og:description" content="{{d}}">|)
        _      -> (lurk|<meta property="og:description" content="{{metaDescription seo}}">|)
    }}
    {{case (ogType seo) of
        Just t -> (lurk|<meta property="og:type" content="{{t}}">|)
        _      -> (lurk|<meta property="og:type" content="website">|)
    }}
    {{case (ogImage seo) of
        Just i -> (lurk|<meta property="og:image" content="{{i}}">|)
        _      -> mempty
    }}
    {{case (ogImageAlt seo) of
        Just i -> (lurk|<meta property="og:image:alt" content="{{i}}">|)
        _      -> mempty
    }}
    {{case (ogUrl seo) of
        Just u -> (lurk|<meta property="og:url" content="{{u}}">|)
        _ -> case (canonical seo) of
                Just c -> (lurk|<meta property="og:url" content="{{c}}">|)
                _      -> mempty
    }}
    {{case (ogSiteName seo) of
        Just n -> (lurk|<meta property="og:site_name" content="{{n}}">|)
        _      -> mempty
    }}
    {{case (twitterCard seo) of
        Just c -> (lurk|<meta name="twitter:card" content="{{c}}">|)
        _      -> (lurk|<meta name="twitter:card" content="{{"summary_large_image"}}">|)
    }}
    {{case (twitterTitle seo) of
        Just t -> (lurk|<meta name="twitter:title" content="{{t}}">|)
        _ -> case (ogTitle seo) of
                Just t -> (lurk|<meta property="og:title" content="{{t}}">|)
                _      -> (lurk|<meta property="og:title" content="{{title seo}}">|)
    }}
    {{case (twitterDescription seo) of
        Just d -> (lurk|<meta name="twitter:description" content="{{d}}">|)
        _ -> case (ogDescription seo) of
                Just d -> (lurk|<meta property="og:description" content="{{d}}">|)
                _ -> (lurk|<meta property="og:description" content="{{metaDescription seo}}">|)
    }}
    {{case (twitterImage seo) of
        Just i -> (lurk|<meta name="twitter:image" content="{{i}}">|)
        _ -> case (ogImage seo) of
                Just i -> (lurk|<meta property="og:image" content="{{i}}">|)
                _ -> mempty
    }}
    {{case (twitterImageAlt seo) of
        Just i -> (lurk|<meta name="twitter:image:alt" content="{{i}}">|)
        _ -> case (ogImageAlt seo) of
                Just i -> (lurk|<meta property="og:image:alt" content="{{i}}">|)
                _ -> mempty
    }}
    {{case (twitterSite seo) of
        Just s -> (lurk|<meta name="twitter:site" content="{{s}}">|)
        _      -> mempty
    }}
    {{case (twitterCreator seo) of
        Just c -> (lurk|<meta name="twitter:creator" content="{{c}}">|)
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