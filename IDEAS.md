# Lurk Ideas

## Code Generators

### `lurk create view ViewName`

Scaffolds `View/ViewName.hs` with the correct module declaration and basic
structure, then registers `View.ViewName` in `other-modules` in the `.cabal`
file (inserted in alphabetical order).

### `lurk create controller ControllerName`

Scaffolds `Controller/ControllerName.hs` with a module declaration and a
stub action, then registers it in `.cabal`.

### `lurk create locale LocaleName`

Scaffolds `Locales/LocaleName.hs` with a module declaration and a stub locale
record, then registers it in `.cabal`.

### `lurk create page ViewName ControllerName`

Composite generator. Creates or updates the following in one command:

- `View/ViewName.hs` — new view module
- `Locales/ViewName.hs` — new locale module
- `Controller/ControllerName.hs` — created if it doesn't exist; if it does,
  appends a new action at the end of the file

**Import handling:**

- *New controller:* full scaffold with all necessary imports.
- *Existing controller:* adds only missing imports, keeping the import block
  sorted. The basics added for a new page are:
  ```haskell
  import Locales.ViewName qualified as ViewName
  import View.ViewName (viewNameView)
  ```

All generated modules are registered in `other-modules` in `.cabal`
(alphabetically, no duplicates).

## `.cabal` Scaffolding

The `.cabal` file itself should be a Lurk scaffold target (`lurk init` or
`lurk new ProjectName`), generating a clean, opinionated template with:

- CalVer versioning (`YYYY.M.D`) instead of PVP — appropriate for websites
  and apps that aren't published libraries.
- Commented-out optional fields (`synopsis`, `description`, `copyright`,
  `extra-doc-files`, `extra-source-files`) so they're easy to fill in without
  noise.
- Pre-configured `common warnings` and `common extensions` stanzas matching
  Lurk's defaults.
- A single `executable` stanza with `import: warnings, extensions` already
  wired up.

### Notes

- `other-modules` auto-generation is trivial: scan `.hs` files, derive module
  names from their paths relative to `hs-source-dirs`.
- `build-depends` auto-generation is non-trivial: requires resolving each
  `import` statement against a package database (`ghc-pkg find-module`), which
  can be ambiguous. Not a priority.

## `Lurk.Env`

Environment management belongs to the framework. Application configuration
belongs to the project. The same separation already applied to routes, SEO,
i18n, and brand data applies here too.

**What Lurk owns:** an opaque `Env` type and the machinery to load and query it.

**What the project owns:** a `Config` data type and a `loadConfig` function
that uses `Lurk.Env` to read whatever variables it actually needs.

### Public API

```haskell
module Lurk.Env
    ( Env
    , loadEnv
    , getEnv
    , getEnvDefault
    , hasEnv
    , requireEnv
    ) where
```

- `loadEnv :: IO Env` — merges system environment variables and `.env` file
  (system takes precedence). Behaviour adapts based on `LURK_ENV`:
  - `development` (default): loads `.env` if present + system env
  - `production`: system env only, `.env` ignored
- `getEnv :: Env -> Text -> Maybe Text`
- `getEnvDefault :: Env -> Text -> Text -> Text`
- `hasEnv :: Env -> Text -> Bool`
- `requireEnv :: Env -> Text -> IO Text` — fails with a clear error if missing

`LURK_ENV` is detected automatically. Projects never pass it as an argument;
they just call `loadEnv`.

### Internals (not exported)

```haskell
newtype Env = Env (Map Text Text)
```

The `Map` is never part of the public API. Projects use `getEnv`/`requireEnv`,
not `Map.lookup`.

### Project-side example

```haskell
module Config where

data Config = Config
    { dbHost    :: Text
    , dbPort    :: Int
    , gaId      :: Maybe Text
    }

loadConfig :: IO Config
loadConfig = do
    env    <- loadEnv
    dbHost <- requireEnv env "DB_HOST"
    dbPort <- requireEnvRead env "DB_PORT"  -- parses to Int
    gaId   <- getEnv env "GA_ID"
    pure Config{..}
```

A site with no database simply doesn't call `requireEnv "DB_HOST"`. Lurk
makes no assumptions about what variables exist.

### Long-term (not v1)

A typeclass for swappable providers would allow:

```haskell
class EnvProvider p where
    loadEnv :: p -> IO Env
-- DotEnvProvider | SystemProvider | VaultProvider | SecretsManagerProvider
```

Not a priority for v1. Start with a single `loadEnv :: IO Env` that handles
the dev/prod distinction automatically.

## `lurk deploy` (future)

```
lurk deploy
```

Could automate the full release pipeline without Lurk knowing a single
variable name:

1. Build binary
2. Upload binary and assets over SSH
3. Generate `.env` from GitHub Secrets (injected by CI)
4. Restart systemd service

The typical flow:

```
GitHub Secrets → GitHub Action → SSH → Server → systemd restart
```

No secrets in Git. No framework opinions about what secrets exist.

## `Lurk.Language` / Project Language Scaffolding

Projects using Lurk for multi-language sites define their own `Language` enum:

```haskell
data Language = EN | ES | KO
    deriving (Eq, Enum, Bounded)
```

Lurk could own the *pattern* (and provide helpers) without owning the *values* (which are project-specific). Two possible directions:

### Option A — Typeclass

```haskell
class LurkLanguage lang where
    defaultLanguage :: lang
    allLanguages    :: [lang]
    langCode        :: lang -> Text   -- "en", "es", "ko"
    langName        :: lang -> Text   -- "English", "Español"
```

Projects implement the instance. Lurk helpers (`getForLangs`, future route generators) are constrained on `LurkLanguage lang`.

### Option B — Code Generator

```
lurk init language EN ES KO
```

Generates `Language.hs` with the enum, `Show` instance, `allLanguages`, `langCode`, and `langName`. No typeclass needed — the file is the contract. Works for the majority of projects where languages are set at init time and rarely change.

**Option B is simpler and better DX** for the target audience (developers coming from PHP/Laravel). No typeclass complexity; the scaffold is the convention.

Not a v1 priority. The current approach (`Language.hs` as a project-level file) works well and can be replaced by this scaffold when the CLI generator is ready.

---

## Default Error Views

Lurk could ship a default `error404View` and `error500View` in a `Lurk.Views` module, allowing projects to get a working error page with zero boilerplate:

```haskell
-- Lurk.Views
error404View :: (?currentPath :: Text) => Html
error500View :: (?currentPath :: Text) => Html
```

Projects that want custom branding/language override by not calling `notFound notFoundAction` from Lurk and defining their own.

The default views would use no locale system — just hardcoded English strings — since Lurk doesn't know the project's `Language` type.

Not a v1 priority. Projects should define `Locales/Error.hs` and their own error view in the meantime.
---

## Page / Route ADT

A type-safe route ADT (`data Page = Home | Pricing | ...`) could live in Lurk and be provided to projects as a scaffold, with compile-time exhaustiveness checking. This would allow the framework to generate localized path helpers automatically and ensure that all routes are handled in the router.

---

## Sessions & CSRF (partially implemented)

### Done

- `Lurk.Session` — InMemoryStore (TVar) + FileStore (persisted to `.lurk-sessions/`), newSessionId (entropy), get/set/delete, cleanup
- `Lurk.Session.Middleware` — WAI middleware for `_session_id` cookie lifecycle, passes session ID via internal `X-Lurk-Session-Id` header
- `Lurk.CSRF` — token generation (32 bytes hex), synchronizer token validation, WAI middleware for POST/PUT/DELETE, form body caching via global TVar (keyed by session ID) for handlers that need re-reading the consumed request body
- `Lurk.App` — `runLurk` creates FileStore, wires session + CSRF middleware, `getSessionIdFromHeaders` helper

### Remaining

1. **Flash messages** — one-time session data for success/error feedback
2. **Session-based auth** — login/logout, user roles
3. **Token rotation** — regenerate on privilege change
4. **Redis store** — for horizontal scaling
5. **Session fixation protection** — regenerate ID on login
6. **CSRF exemptions** — exclude specific routes (webhooks, APIs)
7. **Secure flag in dev** — disable Secure cookie flag when not on HTTPS

## `Lurk.Form` — Reusable Form Processing Pipeline

After building form handlers in a real project (access request, enterprise
inquiry), a clear pattern emerged. The same steps repeat for every form POST:

1. Read cached form params from CSRF middleware's TVar cache
2. Validate time-to-submit (anti-bot, minimum N seconds since page load)
3. Check honeypot field (if filled → redirect to 404)
4. Verify email domain has MX records (DNS check)
5. Run business logic (scoring, logging, email sending)
6. Redirect to thank-you page

Steps 1–4 and 6 are identical across forms. Only step 5 varies.

### Proposed API

```haskell
module Lurk.Form
    ( FormConfig(..)
    , FormResult(..)
    , processForm
    ) where

data FormConfig = FormConfig
    { fcStore         :: SessionStore
    , fcHoneypotField :: Text              -- e.g. "b_website"
    , fcMinSeconds    :: Int               -- e.g. 3
    , fcRedirect      :: Text              -- e.g. "/thanks/"
    , fcHandler       :: [(Text,Text)] -> Action ()  -- business logic
    }

-- | Run the full form pipeline: cache read → honeypot → time check →
-- MX check → handler → redirect. The handler receives cleaned params.
processForm :: FormConfig -> Action ()
```

### What it does NOT own

- **Email sending** — too project-specific (templates, SMTP config, recipients)
- **Lead scoring** — business logic, not a framework concern
- **Logging format** — project decides what to log and where
- **Field validation** — too varied (some forms need phone validation, others
  don't); Lurk provides the anti-abuse layer, projects handle field-level
  validation

### Why this matters

Every Lurk project that adds a form ends up copy-pasting the same anti-abuse
checks (honeypot, time-to-submit, MX verification) and CSRF param extraction.
A `Lurk.Form` module eliminates that duplication while keeping business logic
in the project where it belongs.

The key insight: the framework should own **security and infrastructure**
(honeypot, rate limiting, CSRF, session management) while the project owns
**business logic** (what to do with the data). `Lurk.Form` draws that line
cleanly.

## Component Abstraction

Blade has `@include('components.button')`. React has `<Button />`. Lurk has
functions returning `Html` with no composition mechanism.

Two directions:

### Option A — `@include` in QQ

```haskell
[lurk|
@include "components.option-card" { opt = opt, idx = idx }
|]
```

The QQ resolves `@include` at compile time, inlining the referenced template.
No runtime overhead. The included template has access to the same implicit
parameters.

### Option B — `Lurk.Component` module

```haskell
component :: Text -> [(Text, Html)] -> Html
slot :: Text -> Html -> [(Text, Html)]
```

Projects define components as Haskell functions. Lurk provides the composition
API. More flexible but more boilerplate.

**Option A is better DX** for the target audience. Blade devs expect `@include`,
not function composition.

Not a v1 priority. The current approach (Haskell functions) works.

---

## HTML Escaping Fix

`Lurk.Html.toHtml` only escapes `<`, `>`, and `&`. It does not escape `"`, `'`,
or backtick. This is an XSS risk in attribute contexts:

```haskell
[lurk|<div class="{userInput}">|]
-- If userInput is: " onclick="alert(1)
-- Result: <div class=" " onclick="alert(1)">
```

**Fix:** Add `T.replace "\"" "&quot;"` and `T.replace "'" "&#39;"` to `toHtml`
in `Lurk.Html`. One-line change, real security impact.

---

## QQ Error Messages with Line Numbers

When a QQ expression fails to parse, the error is:
```
Parse error in LURK {} block: unexpected '<' expecting '}'
```
No line number in the template, no suggestion for what went wrong.

The QQ parser already uses megaparsec which tracks `SourcePos`. Exposing
line/column in the error output is straightforward. The template string
offset can be mapped back to a line number by counting newlines.

---

## `postActions` Helper

POST routes must be duplicated per language:
```haskell
postAction (accessPath EN) (accessPostAction EN)
postAction (accessPath ES) (accessPostAction ES)
postAction (accessPath KO) (accessPostAction KO)
```

`getPages` solves this for GET routes. The same pattern works for POST:

```haskell
postActions :: [lang] -> (lang -> Text) -> (lang -> Action ()) -> LurkApp
postActions langs pathFn actionFn =
    mapM_ (\lang -> postAction (pathFn lang) (actionFn lang)) langs
```

Three lines of code. Eliminates per-language POST route duplication.
Naming follows `getPage`/`getPages` → `postAction`/`postActions`.

---

## `Lurk.Opaque` — Bot-Proof Content

A view-level primitive for hiding emails, phone numbers, or any text from
scrapers. The view decides what gets protected — not invisible middleware.

### API

```haskell
module Lurk.Opaque
    ( Opaque
    , email
    , phone
    , opaque
    , renderOpaque
    ) where

-- | Opaque content. Plain for humans, encoded for bots.
newtype Opaque = Opaque Text

-- | Create from a plain email
email :: Text -> Opaque
email = Opaque

-- | Create from a plain phone number
phone :: Text -> Opaque
phone = Opaque

-- | Create from any text
opaque :: Text -> Opaque
opaque = Opaque

-- | Render: True = bot (encoded), False = human (plain)
renderOpaque :: Bool -> Opaque -> Text
renderOpaque isBot (Opaque t)
    | isBot    = T.concatMap (\c -> T.pack $ "&#" ++ show (fromEnum c) ++ ";") t
    | otherwise = t
```

### Usage

```haskell
[lurk|
<p>Contact {renderOpaque isBot (email "hello@foo.com")}</p>
<p>Call {renderOpaque isBot (phone "+1-555-0123")}</p>
|]
```

The `isBot` flag comes from checking the User-Agent header for common bot
strings (Googlebot, Bingbot, etc.). The view decides which emails are public
and which need protection.

### Why not middleware?

Middleware obfuscates everything blindly. `Lurk.Opaque` is a view primitive —
the developer chooses what to protect. A contact page might show the real
email to everyone. A footer might protect it. The choice is in the template,
not invisible infrastructure.

---

## Deployment & Performance

### Binary Stripping
Add a `strip` step to the deployment pipeline to reduce binary size (e.g., from 55MB to ~20MB) and speed up transfers. This removes debugging symbols not needed for production.

### Remote Build Support
Investigate optional remote builds on VPS for projects where VPS RAM > 4GB to leverage incremental builds without local GHC/Cabal requirements.

---

## Template System: `{{expr}}` Syntax

### Problem
The current `{haskell}` interpolation conflicts with CSS `{property: value}` and JS `{key: value}` blocks inside `[lurk|...|]`. Developers must escape or separate styles/scripts.

### Solution
Change Haskell interpolation to `{{expr}}`:
```haskell
[lurk|
<style>
.container { display: flex; }
</style>
<div class="{{cssClass}}">{{userName}}</div>
|]
```

### Implementation
- Update `Lurk.QQ` parser to recognize `{{` and `}}` as delimiters instead of `{` and `}`
- Single `{` and `}` become literal text (CSS/JS just works)
- Backwards incompatible but trivial to migrate (search-replace `{` → `{{` in templates)

---

## Template Control Flow

### `@forEach` / `@forEachIndexed`

```haskell
[lurk|
@forEach items as item
    <div>{{item.name}}</div>
@end

@forEach items as idx, item indexed
    <div>{{idx}}. {{item.name}}</div>
@end
|]
```

### `@if` / `@else`

```haskell
[lurk|
@if isLoggedIn
    <a href="/dashboard">Dashboard</a>
@else
    <a href="/login">Login</a>
@end
|]
```

### `@case` / `@of`

```haskell
[lurk|
@case userRole of
    @of Admin -> <span>Admin Panel</span>
    @of User  -> <span>User Dashboard</span>
    @of Guest -> <span>Public View</span>
@end
|]
```

### Grammar

```
template     ::= (literal | interpolation | forEach | if | case)*
interpolation ::= "{{" expr "}}"
forEach      ::= "@forEach" expr "as" (name | idx "," name "indexed") block
if           ::= "@if" expr block ("@else" block)? block
case         ::= "@case" expr "of" alternative+ block
alternative  ::= "@of" pattern "->" block
block        ::= template "@end"
```

### Implementation Notes
- Parser changes in `Lurk.QQ`: extend `Chunk` data type with new constructors
- `@forEach` generates `mapM_` or `forM_` in TH
- `@if` generates `if ... then ... else` in TH
- `@case` generates `case ... of` in TH
- All expressions have access to `?currentPath` and `?params` implicit parameters

---

## `Lurk.Cloudflare` — Full Cloudflare Integration

Beyond just `cfCountry`. Typed access to Cloudflare edge primitives:

```haskell
module Lurk.Cloudflare
    ( -- | Request headers
      cfCountry        -- Already exists
    , cfContinent
    , cfCity
    , cfRegion
    , cfTimezone
    , cfASN
    , cfBotScore
    , cfBotVerified
      -- | Workers KV (edge caching)
    , kvGet
    , kvPut
    , kvDelete
      -- | D1 (serverless SQL at edge)
    , d1Query
    , d1Execute
      -- | Images (on-the-fly optimization)
    , imageResize
    , imageTransform
      -- | Turnstile (CAPTCHA replacement)
    , turnstileVerify
    ) where
```

### Why This Matters
- Cloudflare is the default for modern web apps
- Typed, safe access to edge primitives from Haskell is a massive DX win
- No more raw header parsing or REST API calls
- `turnstileVerify` replaces reCAPTCHA with Cloudflare's Turnstile

---

## `Lurk.Mail` — Email Abstraction

Current `Controller/Form.hs` has raw SMTP socket code. Lurk should own this:

```haskell
module Lurk.Mail
    ( MailConfig(..)
    , MailMessage(..)
    , sendMail
    ) where

data MailConfig
    = SMTPConfig { smtpHost, smtpUser, smtpPass :: Text, smtpPort :: Int }
    | SendGridConfig { apiKey :: Text }
    | ResendConfig { apiKey :: Text }

data MailMessage = MailMessage
    { from    :: Text
    , to      :: [Text]
    , subject :: Text
    , body    :: Text
    }

sendMail :: MailConfig -> MailMessage -> IO (Either MailError ())
```

### Why
Every web app sends emails. Lurk shouldn't make developers write raw SMTP sockets.

---

## `Lurk.Auth` — Session-Based Authentication

Extend existing session system with auth primitives:

```haskell
module Lurk.Auth
    ( User(..)
    , Role(..)
    , login
    , logout
    , currentUser
    , requireAuth
    , requireRole
    ) where

login        :: SessionStore -> User -> Action ()
logout       :: SessionStore -> Action ()
currentUser  :: SessionStore -> Action (Maybe User)
requireAuth  :: SessionStore -> Action User
requireRole  :: SessionStore -> Role -> Action User
```

---

## `Lurk.Flash` — Flash Messages

One-time session data for success/error feedback:

```haskell
flashSuccess :: Text -> Action ()
flashError   :: Text -> Action ()
flashWarning :: Text -> Action ()
getFlash     :: Action (Maybe Flash)
```

---

## `Lurk.DB` — Type-Safe Database Layer

The "Laravel Killer" feature. No ORM — the Haskell type IS the schema:

```haskell
data User = User
    { userId    :: Int
    , userName  :: Text
    , userEmail :: Text
    } deriving (Generic, DBSchema)

findUser :: Connection -> Int -> IO (Maybe User)
createUser :: Connection -> NewUser -> IO User
```

---

## `Lurk.Cache` — Caching Layer

```haskell
cacheGet    :: CacheStore -> Text -> IO (Maybe a)
cacheSet    :: CacheStore -> Text -> Int -> a -> IO ()
cacheDelete :: CacheStore -> Text -> IO ()
cacheOr     :: CacheStore -> Text -> Int -> IO a -> IO a
```

---

## `Lurk.i18n` — Enhanced Internationalization

Beyond current `Language.hs`:

```haskell
-- Pluralization
t :: Language -> Text -> Int -> Text
t EN "item" 1 = "1 item"
t EN "item" n = show n <> " items"

-- Date formatting
formatDate :: Language -> UTCTime -> Text

-- Currency formatting
formatCurrency :: Language -> Currency -> Text
```

---

## `Lurk.WebSocket` — Real-Time Communication

```haskell
wsHandler :: FromJSON msg => (msg -> Action ()) -> LurkApp ()
broadcast  :: ToJSON msg => msg -> ConnectionPool -> IO ()
sendTo     :: ToJSON msg => ConnectionId -> msg -> IO ()
```

---

## Priority Matrix

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| P0 | `{{expr}}` syntax | Medium | High |
| P0 | `Lurk.Form` | Low | High |
| P1 | `Lurk.Mail` | Low | High |
| P1 | `Lurk.Cloudflare` | Medium | High |
| P1 | `Lurk.Auth` | Medium | High |
| P2 | `@if` / `@forEach` | High | High |
| P2 | `Lurk.Flash` | Low | Medium |
| P3 | `Lurk.DB` | Very High | Very High |
| P3 | `Lurk.i18n` | Medium | Medium |
| P3 | `Lurk.WebSocket` | High | Medium |
| P4 | `Lurk.Cache` | Medium | Medium |
| P4 | `Lurk.WASM` | Very High | Very High |
| P4 | `Lurk.Admin` | Very High | Very High |
