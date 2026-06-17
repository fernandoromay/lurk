{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
module Lurk.SEO
    ( SEO(..)
    , Alternate(..)
    , defaultSEO
    , renderSEO
    ) where

import Data.Text (Text)
import Lurk.Html (Html, concatHtml)
import Lurk.QQ (lurk)

data SEO = SEO
    { title           :: Text
    , metaTitle       :: Text
    , metaDescription :: Text
    , robots          :: Maybe Text
    , canonical       :: Maybe Text
    , alternates      :: [Alternate]
    , ogTitle         :: Maybe Text
    , ogDescription   :: Maybe Text
    , ogType          :: Maybe Text
    , ogImage         :: Maybe Text
    , customTags      :: Html
    }

data Alternate = Alternate
    { hreflang :: Text
    , href     :: Text
    }

defaultSEO :: SEO
defaultSEO = SEO
    { title = "UX Title. Change this, please!"
    , metaTitle = "Search Title. This should be optimized for search engines"
    , metaDescription = "Search Description. This should be optimized for search engines"

    -- Optional fields
    , robots = Nothing
    , canonical = Nothing
    , alternates = []
    , ogTitle = Nothing
    , ogDescription = Nothing
    , ogType = Nothing
    , ogImage = Nothing
    , customTags = mempty
    }

renderSEO :: SEO -> Html
renderSEO seo = [lurk|
    <title>{title seo}</title>
    <meta name="title" content="{metaTitle seo}">
    <meta name="description" content="{metaDescription seo}">
    {renderRobots (robots seo)}
    {renderCanonical (canonical seo)}
    {renderAlternates (alternates seo)}
    {renderOgTitle (ogTitle seo)}
    {renderOgDescription (ogDescription seo)}
    {renderOgType (ogType seo)}
    {renderOgImage (ogImage seo)}
    {customTags seo}
|]
  where
    renderRobots (Just r) = [lurk|<meta name="robots" content="{r}">|]
    renderRobots Nothing  = mempty

    renderCanonical (Just c) = [lurk|<link rel="canonical" href="{c}">|]
    renderCanonical Nothing  = mempty

    renderAlternates = concatHtml . map (\a ->
        [lurk|<link rel="alternate" hreflang="{hreflang a}" href="{href a}">|])

    renderOgTitle (Just t) = [lurk|<meta property="og:title" content="{t}">|]
    renderOgTitle Nothing  = mempty

    renderOgDescription (Just d) = [lurk|<meta property="og:description" content="{d}">|]
    renderOgDescription Nothing  = mempty

    renderOgType (Just t) = [lurk|<meta property="og:type" content="{t}">|]
    renderOgType Nothing  = mempty

    renderOgImage (Just i) = [lurk|<meta property="og:image" content="{i}">|]
    renderOgImage Nothing  = mempty
