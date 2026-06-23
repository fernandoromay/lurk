module View.Layout.Default where

import Paths (pageAlts, domain)
import View.Prelude
import View.Partial

defaultLayout :: ViewCtx Language => SEO -> Html -> Html
defaultLayout seo viewContent = [lurk|
<!DOCTYPE html>
<html lang="{{toText ?lang}}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="color-scheme" content="light dark">
    <link rel="icon" type="image/svg+xml" href="{{assetPath "img/favicon.svg"}}">

    <!-- Styles -->
    <link rel="stylesheet" href="{{assetPath "css/common.css"}}">

    {{renderSEO seo}}

    {{renderAlternates domain pageAlts}}

</head>
<body>
    {{navbar}}

    {{viewContent}}

    {{footer}}

    <script src="{{assetPath "js/common.js"}}"></script>
</body>
</html>
|]
