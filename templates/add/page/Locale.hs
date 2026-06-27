module {{ModPrefix}}Locale.{{PascalName}} where

import {{ModPrefix}}Locale.Prelude

data {{PascalName}}Locale = {{PascalName}}Locale
    { seo :: SEO
    , title :: Text
    , description :: Text
    }

commonSeo :: SEO
commonSeo = defaultSEO

{{language-implementations}}
