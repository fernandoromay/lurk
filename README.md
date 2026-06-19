# Lurk (Lean Unified Rendering Kernel)

Lurk is the **L**ean **U**nified **R**endering **K**ernel.

It is a lightweight, high-performance Haskell web framework designed for maximum developer experience and uncompromising type safety. Lurk compiles your entire application—including HTML templates and multi-language routing—into a single native binary. With instant cold starts, a minimal ~10MB memory footprint, and compile-time variable checking, Lurk catches template typos and missing translations before the code ever runs.

## Features

- **`[lurk|...|]` Quasiquoter** — HTML templates with compile-time variable checking. Typos are build errors, not runtime blanks.
- **Type-safe i18n** — Missing translations are compile errors. Routes are generated for all languages in one call.
- **Session + CSRF** — File-backed sessions with automatic CSRF validation on POST routes.
- **Environment** — Opaque `Env` type with `getEnv`/`requireEnv`/`hasEnv`. Loads `.env` at startup.
- **Deployment** — `lurk deploy` builds a binary and deploys it via SSH or Docker.
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
│   ├── Routes.hs         # getPages, postActions, routeSettings, notFound
│   ├── Request.hs        # Request helpers (params, headers, cookies)
│   ├── Env.hs            # loadEnv, getEnv, requireEnv
│   ├── Session.hs        # File-backed session store (TVar)
│   ├── Session/
│   │   └── Middleware.hs  # WAI middleware for session handling
│   ├── CSRF.hs           # CSRF token generation and validation
│   ├── Cookie.hs         # Cookie helpers
│   ├── SEO.hs            # SEO data types (title, meta, OG, structured data)
│   ├── Assets.hs         # mkAssetPath, fingerprinted asset URLs
│   ├── Language.hs        # Language typeclass for i18n
│   ├── Deploy.hs         # DeployProvider typeclass
│   └── Deploy/
│       ├── SSH.hs        # SSH deployment provider
│       ├── Docker.hs     # Docker deployment provider
│       └── Shell.hs      # Shell command runner
├── cli/
│   └── Main.hs           # `lurk` CLI (deploy, build)
├── test/
│   ├── Main.hs
│   ├── SessionSpec.hs
│   └── CSRFSpec.hs
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
import Language (allLanguages)

router :: LurkApp
router = do
    routeSettings [ TrailingSlashes, ForceSSL, ServeStatic "public" ]
    getPages allLanguages homePath homeAction
    postActions allLanguages contactPath contactPostAction
    notFound notFoundAction
```

### 3. Write views with `[lurk|...|]`

```haskell
homeView :: Language -> Html
homeView lang = [lurk|
  <html>
  <body>
    <h1>{{heroTitle}}</h1>
    <a href="{{ctaLink}}">{{ctaText}}</a>
  </body>
  </html>
|]
  where
    heroTitle = case lang of
      EN -> "Hello World"
      ES -> "Hola Mundo"
    ctaText = "Get Started"
    ctaLink = "/access/"
```

Variables are checked at compile time. A typo like `{{heroTitel}}` fails the build.

### 4. Handle forms

```haskell
contactPostAction :: Language -> Action ()
contactPostAction lang = do
    params <- readFormParams

    -- Anti-abuse checks
    let honeypot = lookupParam "b_website" params
    unless (T.null honeypot) $ redirect "/404/"

    tooFast <- checkTimeToSubmit 3 params
    unless tooFast $ redirect "/404/"

    -- Process form...
    redirect "/thanks/"
```

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

### `getPages` / `postActions`

Register routes for all languages:

```haskell
getPages :: [Language] -> (Language -> Text) -> (Language -> Action ()) -> LurkApp
postActions :: [Language] -> (Language -> Text) -> (Language -> Action ()) -> LurkApp
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

Two syntaxes for embedding inner HTML blocks:

**`[lurk|...|]`** — bracket nesting (for use inside `{{ }}` expressions):

```haskell
[lurk|
  <ul>
    {{foldMap (\item -> [lurk|
      <li>{{item.title}}</li>
    |]) items}}
  </ul>
|]
```

**(lurk|...|)** — parenthesis nesting (for inline lambdas):

```haskell
[lurk|
  <div class="agents">
    {{forEach agents (\a -> (lurk|
      <div class="agent-card">
        <h4>{{a.name}}</h4>
        <p>{{a.description}}</p>
      </div>
    |))}}
  </div>
|]
```

Both track nesting depth — inner blocks can contain further nested `[lurk|...|]` or `(lurk|...|)` without escaping issues.

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

File-backed sessions with TVar storage:

```haskell
store <- getStore
Session.setSessionValue store sid "key" "value"
sess <- Session.getSession store
val <- Session.getSessionValue "key" sess
```

### `Lurk.CSRF`

Automatic CSRF protection on POST routes. Tokens are generated per-session and validated in middleware.

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

## Planned

- `Lurk.Form` — Form handling with anti-abuse built-in
- `Lurk.Mail` — Email abstraction layer
- `Lurk.Flash` — Flash messages
- `Lurk.Auth` — Authentication primitives
- `Lurk.DB` — Database/ORM layer
- `Lurk.WebSocket` — WebSocket support
- `lurk create page` — CLI scaffolding

## Testing

```bash
cabal test lurk-tests
```

Tests cover session management and CSRF token handling.

## License

MIT
