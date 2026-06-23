module View.Partial where

import Data.Text qualified as T
import Paths (pageAlts)
import View.Prelude
import Locale.Partial

navbar :: ViewCtx Language => Html
navbar = [lurk|
<header>
  <nav class="navbar-top">
    <div class="container">
      <a href="{{l.homeLink}}" class="navbar-brand">
        <div class="logo-h"></div>
      </a>

      <ul class="navbar-nav">
        <li><a href="{{l.homeLink}}" class='{{if ?currentPath == l.homeLink then "active" else ""}}'>{{l.homeText}}</a></li>
      </ul>

      <div class="d-flex gap-4 justify-content-center">
        {{forEach pageAlts (\(langCode, path) ->
          (lurk|
            <a href="{{path}}" class='{{if langCode == toText ?lang then "accented fw-bold" else ""}}'>{{T.toUpper langCode}}</a>
          |))
        }}
      </div>
    </div>
  </nav>
</header>
|]
  where
    l = navbarLocale ?lang

    isActive :: (?currentPath :: Text) => Text -> Text
    isActive path
      | (path `isSubpath` ?currentPath) && (path /= "/") = "active"
      | otherwise = ""


footer :: (?lang :: Language) => Html
footer = [lurk|
<footer>
  <div class="row">

  <div class="footer-bottom">
    <div class="notice">
      {{l.notice}}
    </div>
  </div>
</footer>
|]
  where
    l = footerLocale ?lang
    nav = navbarLocale ?lang
