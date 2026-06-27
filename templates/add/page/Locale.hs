module Locale.{{PascalName}} where

import Locale.Prelude

data {{PascalName}}Locale = {{PascalName}}Locale
    { seo :: SEO
    , title :: Text
    , description :: Text
    }

commonSeo :: SEO
commonSeo = defaultSEO

{{language-implementations}}
