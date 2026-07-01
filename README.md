# Lurk (Lean Unified Rendering Kernel)

Lurk is the **L**ean **U**nified **R**endering **K**ernel.

Lurk is a lightweight, high-performance Haskell web framework built for **any** Haskell developer. It provides a complete toolkit—HTML templates with compile-time checking, sessions, CSRF protection, form handling, i18n routing, email, and deployment—so you can build type-safe web applications without gluing together a dozen libraries.

Lurk compiles your entire application—including HTML templates and multi-language routing—into a single native binary. With instant cold starts, a minimal ~10MB memory footprint, and compile-time variable checking, Lurk catches template typos and missing translations before the code ever runs.

## Features

- **`[lurk|...|]` Quasiquoter:** HTML templates with compile-time variable checking. Typos are build errors, not runtime blanks.
- **Type-safe i18n:** Missing translations are compile errors. Routes are generated for all languages in one call. Implicit `?lang` parameter eliminates manual threading.
- **Session + CSRF:** File-backed sessions with automatic CSRF validation on POST routes. Secure cookies in production, atomic file writes, session ID validation.
- **`Lurk.Flash`:** One-time session-based messages for success/error feedback.
- **`Lurk.Form`:** Composable anti-abuse pipeline: honeypot, timing, MX verification, field length. Guards run in `Action` for session access.
- **`Lurk.Email.SMTP`:** Self-contained SMTP client (STARTTLS/SMTPS). Zero external email library dependencies.
- **`Lurk.Routes.Security`:** HTTP security headers middleware (X-Content-Type-Options, X-Frame-Options, HSTS, etc.). Merge API for overrides.
- **`Lurk.Error`:** Default 404/500 error views (self-contained HTML). Exception middleware catches unhandled errors automatically.
- **`Lurk.Log`:** Structured JSON logging with `Logger` record, per-level helpers, file output, and configurable minimum log level.
- **Environment:** Direct OS environment access via `getEnv`/`requireEnv`/`hasEnv`. Reads `.env` at startup with `loadEnv`.
- **Deployment:** `lurk deploy` builds a binary and deploys it via SSH, Docker, or custom shell scripts.
- **Static assets:** `mkAssetPath` for fingerprinted asset URLs.
- **SEO:** Structured data types for title, meta, canonical, OpenGraph, structured data.

## Quick Start

### 1. Install Lurk

In your project directory:
```bash
git submodule add https://github.com/fernandoromay/lurk.git lib/lurk
```

Install the CLI:
```bash
cd lib/lurk/
cabal install exe:lurk
```

Update to latest:
```bash
cd lib/lurk/
git pull
cabal install exe:lurk --overwrite-policy=always 2>&1
```

### 2. Create a project

```bash
lurk new website
```

### 3. Run it

```bash
lurk run
```

Starts the dev server at the port defined in your `AppConfig`.

### 4. Add a page

```bash
lurk add page "About"
```

Generates `View/About.hs` and `Locale/About.hs`, injects paths, controller action, and GET route.

### 5. Add a form

```bash
lurk add form
```

Interactive scaffolding that generates controller, view, route, guards, flash, and CSRF — all layers at once.

---

## Core API

### `Lurk.Prelude`

Re-exports everything needed for a typical web app:

```haskell
import Lurk.Prelude  -- Html, Action, Text, getEnv, render, redirect, etc.
```

### Routes

Register routes for all languages. The action receives `?lang` implicitly:

```haskell
get homePath homeAction
post contactPath contactPostAction
```

`getSubset`/`postSubset` register a subset of languages. `getSingle`/`postSingle` register a single route without language.

### `[lurk|...|]` Quasiquoter

Compile-time HTML templates with `{{expr}}` interpolation. Expressions inside `{{ }}` are full Haskell:

```haskell
[lurk|
  <div class="{{cssClass}}">{{title}}</div>
  <p>{{T.toUpper name}}</p>
|]
```

Use **(lurk|...|)** for inner HTML blocks:

```haskell
[lurk|
  <ul>
    {{forEach items (\item -> (lurk|
      <li>{{item.title}}</li>
    |))}}
  </ul>
|]
```

> **Note:** `[lurk|...|]` nesting inside `{{ }}` is not possible due to GHC constraints. Always use `(lurk|...|)` for inner blocks.

### Implicit Language (`?lang`)

Lurk uses Haskell's `ImplicitParams` to thread language through your app. Define your language type with `Enum` and `Bounded`:

```haskell
data Language = EN | ES | KO
    deriving (Eq, Enum, Bounded)
```

`get`/`post` bind `?lang` automatically. Controllers and views access it implicitly:

```haskell
-- Controller
homeAction :: (?lang :: Language) => Action ()
homeAction = render $ homeView (locale ?lang)

-- View
homeView :: ViewCtx Language => Locale -> Html
homeView locale = defaultLayout seo [lurk|
  <html lang="{{toText ?lang}}">
    ...
  </html>
|]
```

`ViewCtx` expands to:

```haskell
type ViewCtx lang = (?ctx :: ViewContext, ?lang :: lang)
```

### `Lurk.Session`

File-backed sessions with TVar storage. The session store is threaded through each request via the WAI Vault:

```haskell
getSession      :: SessionStore -> Action Session
getSessionValue :: Text -> Session -> Maybe Text
setSessionValue :: SessionStore -> SessionId -> Text -> Text -> Action ()
destroySession  :: SessionStore -> SessionId -> IO ()
```

### `Lurk.Flash`

One-time session-based messages:

```haskell
flashSuccess "Saved!"
flashError   "Something went wrong"
flashWarning "Please review"

-- Access in views via ViewContext
flash :: (?ctx :: ViewContext) => Maybe Flash
```

### `Lurk.Form`

Composable form processing with built-in security guards:

```haskell
fd <- runGuards
    [ honeypot "b_website" (redirect "/404/")
    , minSubmitTime 3 (redirect "/404/")
    , mxRecord "email" (redirect "/404/")
    , maxLength "name" 200 (redirect "/404/")
    ]

let name  = getParamDef "name" "" fd
    email = getParamDef "email" "" fd
```

---

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

## Testing

```bash
cabal test lurk-tests
```

## License

MIT
