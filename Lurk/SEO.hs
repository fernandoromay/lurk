{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
module Lurk.SEO
    ( SEO(..)
    , defaultSEO
    , renderSEO
    ) where

import Data.Text (Text)
import Lurk.Html (Html, concatHtml, preEscapedToHtml)
import Lurk.QQ (lurk)

data SEO = SEO
    { pageTitle     :: Text
    , title         :: Text
    , description   :: Text
    , canonical     :: Maybe Text
    , ogTitle       :: Maybe Text
    , ogDescription :: Maybe Text
    , ogType        :: Maybe Text
    , ogImage       :: Maybe Text
    , customTags    :: Html
    }

-- | Requires the three most important tags to be provided, preventing devs
-- from leaving them blank accidentally.
defaultSEO :: Text -> Text -> Text -> SEO
defaultSEO pt t d =
    SEO
        { pageTitle = pt
        , title = t
        , description = d
        , canonical = Nothing
        , ogTitle = Nothing
        , ogDescription = Nothing
        , ogType = Nothing
        , ogImage = Nothing
        , customTags = mempty
        }

renderSEO :: SEO -> Html
renderSEO seo = [lurk|
    <title>{seo.pageTitle}</title>
    <meta name="title" content="{seo.title}">
    <meta name="description" content="{seo.description}">
    {renderCanonical seo.canonical}
    {renderOgTitle seo.ogTitle}
    {renderOgDescription seo.ogDescription}
    {renderOgType seo.ogType}
    {renderOgImage seo.ogImage}
    {seo.customTags}
|]
  where
    renderCanonical (Just c) = [lurk|<link rel="canonical" href="{c}">|]
    renderCanonical Nothing  = mempty

    renderOgTitle (Just t) = [lurk|<meta property="og:title" content="{t}">|]
    renderOgTitle Nothing  = mempty

    renderOgDescription (Just d) = [lurk|<meta property="og:description" content="{d}">|]
    renderOgDescription Nothing  = mempty

    renderOgType (Just t) = [lurk|<meta property="og:type" content="{t}">|]
    renderOgType Nothing  = mempty

    renderOgImage (Just i) = [lurk|<meta property="og:image" content="{i}">|]
    renderOgImage Nothing  = mempty
