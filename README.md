# Lurk (Lean Unified Rendering Kernel)

Lurk is the **L**ean **U**nified **R**endering **K**ernel.

Lurk is a lightweight, high-performance Haskell web framework built for **any** Haskell developer. It provides a complete toolkit—HTML templates with compile-time checking, sessions, CSRF protection, form handling, i18n routing, email, and deployment—so you can build type-safe web applications without gluing together a dozen libraries.

Lurk compiles your entire application—including HTML templates and multi-language routing—into a single native binary. With instant cold starts, a minimal ~10MB memory footprint, and compile-time variable checking, Lurk catches template typos and missing translations before the code ever runs.

## Features

- **`[lurk|...|]` Quasiquoter** — HTML templates with compile-time variable checking. Typos are build errors, not runtime blanks.
- **Type-safe i18n** — Missing translations are compile errors. Routes are generated for all languages in one call. Implicit `?lang` parameter eliminates manual threading.
- **Session + CSRF** — File-backed sessions with automatic CSRF validation on POST routes. Secure cookies in production, atomic file writes, session ID validation.
- **`Lurk.Flash`** — One-time session-based messages for success/error feedback.
- **`Lurk.Form`** — Composable anti-abuse pipeline: honeypot, timing, MX verification, field length. Guards run in `Action` for session access.
- **`Lurk.Email.SMTP`** — Self-contained SMTP client (STARTTLS/SMTPS). Zero external email library dependencies.
- **Environment** — Opaque `Env` type with `getEnv`/`requireEnv`/`hasEnv`. Loads `.env` at startup.
- **Deployment** — `lurk deploy` builds a binary and deploys it via SSH, Docker, or custom shell scripts.
- **Static assets** — `mkAssetPath` for fingerprinted asset URLs.
- **SEO** — Structured data types for title, meta, canonical, OpenGraph, structured data.

## Project Structure

```
lib/lurk/
├── Lurk/
│   ├── Prelude.hs        # Re-exports everything you need (Html, Action, etc.)
│   ├── App.hs            # runLurk — starts the Warp server
│   ├── QQ.hs             # [lurk|...|] quasiquoter (Template Haskell)
│   ├── Html.hs           # Html type, renderHtml, ToHtml class
│   ├── Flash.hs          # Flash messages (one-time session data)
│   ├── Form.hs           # FormData, FormGuard, withForm, built-in guards
│   ├── Routes.hs         # redirect, currentPath, trailingSlash
│   ├── Request.hs        # Request helpers (params, headers, cookies)
│   ├── Env.hs            # loadEnv, getEnv, requireEnv
│   ├── Session.hs        # File-backed session store (TVar) with destroySession
│   ├── Session/
│   │   └── Middleware.hs  # WAI middleware for session handling (Secure flag, eager expiry)
│   ├── CSRF.hs           # CSRF token generation and validation
│   ├── Cookie.hs         # Cookie helpers
│   ├── SEO.hs            # SEO data types (title, meta, OG, structured data)
│   ├── Assets.hs         # mkAssetPath, fingerprinted asset URLs
│   ├── Language.hs        # Language type, withLang, allLanguages, toText
│   ├── Email/
│   │   └── SMTP.hs       # Self-contained SMTP client (STARTTLS/SMTPS)
│   ├── Deploy.hs         # DeployProvider typeclass
│   └── Deploy/
│       ├── SSH.hs        # SSH deployment provider
│       ├── Docker.hs     # Docker deployment provider
│       └── Shell.hs      # Shell command runner
├── cli/
│   └── Main.hs           # `lurk` CLI (deploy, build, run, kill)
├── test/
│   ├── Main.hs
│   ├── SessionSpec.hs
│   ├── CSRFSpec.hs
│   ├── FlashSpec.hs
│   └── SMTPSpec.hs
├── lurk.cabal
└── CHANGELOG.md
```

## Quick Start

### 1. Add Lurk to your project

In `cabal.project`:
```
packages: lib/lurk
```

In your `.cabal` file:
```cabal
build-depends: lurk
```

### 2. Define routes

```haskell
module Router where

import Lurk.Prelude

router :: LurkApp
router = do
    routeSettings [ TrailingSlashes, ForceSSL, ServeStatic "public" ]
    get homePath homeAction
    post contactPath contactPostAction
    notFound notFoundAction
```

### 3. Write views with `[lurk|...|]`

```haskell
homeView :: ViewCtx Language => Locale -> Html
homeView locale = defaultLayout seo [lurk|
  <html lang="{{toText ?lang}}">
  <body>
    <h1>{{heroTitle}}</h1>
    <a href="{{ctaLink}}">{{ctaText}}</a>
  </body>
  </html>
|]
  where
    heroTitle = case ?lang of
      EN -> "Hello World"
      ES -> "Hola Mundo"
    ctaText = locale.ctaText
    ctaLink = locale.ctaLink
```

Variables are checked at compile time. A typo like `{{heroTitel}}` fails the build.

### 4. Handle forms

```haskell
contactPostAction :: (?lang :: Language) => Action ()
contactPostAction = do
    fd <- validateForm
        [ honeypot "b_website" (redirect "/404/")
        , minSubmitTime 3 (redirect "/404/")
        , mxRecord "email" (redirect "/404/")
        , maxLength "name" 200 (redirect "/404/")
        ]

    let name  = getParamDef "name" "" fd
        email = getParamDef "email" "" fd
    -- Process form...
    redirect "/thanks/"
```

Guards run in sequence. First failure triggers the fallback action and short-circuits. `validateForm` returns validated `FormData` on success.

### 5. Load environment config

```haskell
loadConfig :: IO Config
loadConfig = do
    env <- loadEnv
    pure Config
        { port = fromMaybe 3003 (getEnvInt env "PORT")
        , domain = requireEnv env "DOMAIN"
        }
```

## Core API

### `Lurk.Prelude`

Re-exports everything needed for a typical web app:

```haskell
import Lurk.Prelude  -- Html, Action, Text, getEnv, render, redirect, etc.
```

### `get` / `post`

Register routes for all languages. The action receives `?lang` implicitly:

```haskell
get :: (Enum lang, Bounded lang)
    => (lang -> Text) -> ((?lang :: lang) => Action ()) -> LurkApp
post :: (Enum lang, Bounded lang)
     => (lang -> Text) -> ((?lang :: lang) => Action ()) -> LurkApp
```

`getPages`/`postActions` remain available for edge cases (explicit language lists):

```haskell
getPages :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
postActions :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
```

### Implicit Language (`?lang`)

Lurk uses Haskell's `ImplicitParams` to thread language through your app without explicit parameters. Define your language type with `Enum` and `Bounded`:

```haskell
data Language = EN | ES | KO
    deriving (Eq, Enum, Bounded)
```

`get`/`post` bind `?lang` automatically. Controllers and views access it implicitly:

```haskell
-- Controller: ?lang comes from the router
homeAction :: (?lang :: Language) => Action ()
homeAction = render $ homeView (getLocale ?lang)

-- View: uses ViewCtx for the full implicit context
homeView :: ViewCtx Language => Locale -> Html
homeView locale = defaultLayout seo [lurk|
  <html lang="{{toText ?lang}}">
    {{navbar}}
    ...
  </html>
|]

-- Partial: no explicit lang parameter
navbar :: ViewCtx Language => Html
navbar = [lurk|...{{navbarLocale ?lang}}...|]
```

`ViewCtx` expands to:

```haskell
type ViewCtx lang = (?currentPath :: Text, ?params :: [(Text, Text)], ?lang :: lang)
```

The `lang` type variable is polymorphic — use your own language type. Single-language projects work unchanged: `data Language = EN deriving (Eq, Enum, Bounded)`.

### Flow

```
Router:  get homePath homeAction
           └─ binds ?lang for each language (EN, ES, KO)
Controller: homeAction  (?lang :: Language => Action ())
           └─ passes ?lang to view via implicit scope
View:    homeView  (?currentPath, ?params, ?lang => Html)
           └─ renders with ?lang in scope
```

### `[lurk|...|]` Quasiquoter

Compile-time HTML templates with `{{expr}}` interpolation. Expressions inside `{{ }}` are full Haskell — not just variables:

```haskell
[lurk|
  <div class="{{cssClass}}">{{title}}</div>
  <p>{{T.toUpper name}}</p>
  <span>{{show price <> " USD"}}</span>
|]
```

Multi-line expressions work too:

```haskell
[lurk|
  <div>
    {{case lang of
      EN -> "Hello"
      ES -> "Hola"
      KO -> "안녕하세요"}}
  </div>
|]
```

### Nested Quasiquoters

Use **(lurk|...|)** for embedding inner HTML blocks inside `{{ }}` expressions:

```haskell
[lurk|
  <ul>
    {{forEach items (\item -> (lurk|
      <li>{{item.title}}</li>
    |))}}
  </ul>
|]
```

Parenthesis nesting tracks depth — inner blocks can contain further nested `(lurk|...|)` without escaping issues.

> **Note:** `[lurk|...|]` nesting inside `{{ }}` is broken. GHC cannot parse `|]` inside `|]`. Always use `(lurk|...|)` for inner blocks.

### `forEach` / `forEachWithIndex`

Convenience aliases for rendering lists:

```haskell
forEach :: Foldable t => t a -> (a -> Html) -> Html
forEachWithIndex :: Foldable t => t a -> (Int -> a -> Html) -> Html
```

`forEach` is just `flip foldMap`. `forEachWithIndex` passes a 1-based index:

```haskell
[lurk|
  <div>
    {{forEach items (\item -> (lurk|
      <div class="card">{{item.title}}</div>
    |))}}
  </div>

  <ol>
    {{forEachWithIndex items (\i item -> (lurk|
      <li>{{show i <> ". " <> item.title}}</li>
    |))}}
  </ol>
|]
```

### `renderHtml`

Renders HTML to `Text` (for email templates, etc.):

```haskell
html <- renderHtml [lurk|<p>Hello {{name}}</p>|]
```

### `Lurk.Env`

Type-safe environment access:

```haskell
env <- loadEnv
getEnv env "PORT"        -- Maybe Text
requireEnv env "PORT"    -- Text (throws if missing)
getEnvInt env "PORT"     -- Maybe Int
hasEnv env "PORT"        -- Bool
```

### `Lurk.Session`

File-backed sessions with TVar storage. Includes `destroySession` for logout support and `cleanupSessions` for periodic expiry:

```haskell
store <- getStore
Session.setSessionValue store sid "key" "value"
sess <- Session.getSession store
val <- Session.getSessionValue "key" sess
destroySession store sid        -- remove session (logout)
cleanupSessions store           -- remove expired sessions
```

Cookies use the `Secure` flag in production (detected via `LURK_ENV`). Session ID validation prevents path traversal. Atomic file writes prevent corruption.

### `Lurk.CSRF`

Automatic CSRF protection on POST routes. Tokens are generated per-session and validated in middleware.

### `Lurk.Flash`

One-time session-based messages:

```haskell
flashSuccess "Saved!"
flashError   "Something went wrong"
flashWarning "Please review"
flash        Custom "text" "Custom level message"
msg <- getFlash :: Action (Maybe Flash)
```

Convenience helpers:

```haskell
onFlashSuccess :: Text -> Action ()
onFlashError   :: Text -> Action ()
onFlashWarning :: Text -> Action ()
```

Rendering with auto-dismiss:

```haskell
renderFlash :: Flash -> Html    -- includes auto-dismiss after 5s
renderFlashMaybe :: Action Html  -- renders or empty
```

### `Lurk.Form`

Composable form processing with built-in security guards:

```haskell
-- Run guards and return validated data
validateForm :: [FormGuard] -> Action FormData

-- Extraction helpers
getParam       :: Text -> FormData -> Maybe Text
getParamDef    :: Text -> Text -> FormData -> Text
parseParam     :: Read a => Text -> FormData -> Maybe a

-- Built-in guards (fallback runs on failure, e.g. redirect)
honeypot       :: Text -> Action () -> FormGuard       -- hidden field must be empty
minSubmitTime  :: Int -> Action () -> FormGuard        -- session-backed timing check
mxRecord       :: Text -> Action () -> FormGuard       -- DNS MX verification
maxLength      :: Text -> Int -> Action () -> FormGuard -- field length limit

-- Session helper
setFormLoadTime :: Action ()  -- call when rendering form for minSubmitTime
```

### `Lurk.Email.SMTP`

Self-contained SMTP client with no external email library dependencies:

```haskell
sendEmail :: SmtpConfig -> Email -> IO (Either EmailError ())
```

Supports STARTTLS (port 587) and SMTPS (port 465) with automatic detection. Includes AUTH LOGIN, multi-line response parsing, and 30-second timeout.

### `Lurk.Deploy`

```haskell
lurk deploy  -- builds binary, uploads via SSH, restarts service
```

Configured via `lurk.yaml`:

```yaml
project: my-app
build:
  optimize: true
  target: x86_64-linux
deploy:
  provider: ssh
  config:
    host: example.com
    path: /var/www/my-app
    user: deploy
    service_name: my-app
    activate_cmd: sudo systemctl restart my-app
  env_vars:
    DATABASE_URL: DATABASE_URL
```

## Competitive Advantages

| Feature | Lurk | Laravel | Next.js | Django | Rails |
|---------|------|---------|---------|--------|-------|
| Language | Haskell | PHP | TypeScript | Python | Ruby |
| Type safety | Compile-time | Runtime | TS only | Runtime | Runtime |
| Template errors | Build error | Runtime blank | Build error | Runtime blank | Runtime blank |
| Binary size | ~55MB | N/A | N/A | N/A | N/A |
| Memory | ~10MB | ~30MB | ~50MB | ~30MB | ~40MB |
| Cold start | Instant | Fast | Cold | Moderate | Moderate |
| i18n safety | Compile error | Runtime | Runtime | Runtime | Runtime |
| CSRF | Automatic | Manual token | Manual | Middleware | Middleware |
| Session | File-backed | File/Redis/DB | Cookie | Cookie/DB | Cookie/DB |
| Form guards | Pipeline | Manual rules | Manual | Manual | Manual |
| Flash messages | Built-in | Session flash | N/A | N/A | N/A |

## Planned

- `Lurk.Auth` — Authentication primitives
- `Lurk.Email` — HTTP-based email providers (Mailgun, SendGrid, Resend)
- `Lurk.DB` — Database/ORM layer
- `Lurk.WebSocket` — WebSocket support
- `lurk create page` — CLI scaffolding

## Testing

```bash
cabal test lurk-tests
```

Tests cover session management (file-backed store, atomic writes, cleanup), CSRF token handling, flash messages (data types, rendering, session integration), and SMTP error handling.

## License

MIT
