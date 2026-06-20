# Lurk Ideas

---

## Easy (days)

### Default Error Views

Ship `error404View` and `error500View` in a `Lurk.Views` module. Hardcoded
English strings. Projects that want custom branding override by defining
their own.

---

## Medium (weeks)

### `Lurk.Email` — HTTP-Based Providers (Future)

Extend the email namespace with API-based providers:

```haskell
data MailConfig
    = SMTPConfig { ... }       -- done (Lurk.Email.SMTP)
    | MailgunConfig { apiKey :: Text, domain :: Text }
    | SendgridConfig { apiKey :: Text }
    | ResendConfig { apiKey :: Text }

sendMail :: MailConfig -> MailMessage -> IO (Either MailError ())
```

### `Lurk.Email.Inbound` — Inbound Email (Future)

Receive emails via webhooks (Mailgun/SendGrid POST) or IMAP polling.
Modern web apps use webhooks, not long-lived IMAP connections.

### `Lurk.Opaque` — Bot-Proof Content

View-level primitive for hiding emails/phones from scrapers:

```haskell
newtype Opaque = Opaque Text

email :: Text -> Opaque
phone :: Text -> Opaque
renderOpaque :: Bool -> Opaque -> Text  -- True = bot, False = human
```

```haskell
[lurk|
<p>{renderOpaque isBot (email "hello@foo.com")}</p>
|]
```

The view decides what gets protected. Not invisible middleware. It can even be generalized to obfuscate forms or other sensitive elements, reducing the risk of bots reaching out.

### `Lurk.Cloudflare` — Typed Cloudflare Headers

Beyond just `cfCountry`:

```haskell
cfContinent  :: Action (Maybe Text)
cfCity       :: Action (Maybe Text)
cfRegion     :: Action (Maybe Text)
cfTimezone   :: Action (Maybe Text)
cfASN        :: Action (Maybe Text)
cfBotScore   :: Action (Maybe Text)
cfBotVerified :: Action (Maybe Bool)
turnstileVerify :: Text -> IO Bool  -- CAPTCHA replacement
```

### `Lurk.Auth` — Session-Based Authentication

Extend existing session system:

```haskell
login        :: SessionStore -> User -> Action ()
logout       :: SessionStore -> Action ()
currentUser  :: SessionStore -> Action (Maybe User)
requireAuth  :: SessionStore -> Action User
requireRole  :: SessionStore -> Role -> Action User
```

### VS Code Error Diagnostics for Lurk Blocks

Detect at edit time via Language Server or VS Code diagnostics API:
- Unclosed `{{` or `}}`
- Unclosed `[lurk|` or `(lurk|`
- Missing `|]` or `|)` terminators
- `{{ }}` with empty content
- Nested `[lurk|` without matching close

---

## Hard (months)

### `lurk create page` — CLI Scaffolding

```bash
lurk create page ViewName ControllerName
```

Generates `View/ViewName.hs`, `Locales/ViewName.hs`, creates or updates
`Controller/ControllerName.hs`, registers in `.cabal`.

Also: `lurk create view`, `lurk create controller`, `lurk create locale`.

### `.cabal` Scaffolding

`lurk init` or `lurk new ProjectName` generates a clean template with
CalVer versioning, pre-configured warnings/extensions, single executable.

### Page / Route ADT

Type-safe route ADT (`data Page = Home | Pricing | ...`) with compile-time
exhaustiveness checking and auto-generated localized path helpers.

---

## Very Hard (quarters)

### `Lurk.DB` — Type-Safe Database Layer

The Haskell type IS the schema. No ORM:

```haskell
data User = User
    { userId    :: Int
    , userName  :: Text
    , userEmail :: Text
    } deriving (Generic, DBSchema)

findUser :: Connection -> Int -> IO (Maybe User)
createUser :: Connection -> NewUser -> IO User
```

### `Lurk.i18n` — Enhanced Internationalization

Date formatting, currency formatting:

```haskell
formatDate :: Language -> UTCTime -> Text
formatCurrency :: Language -> Currency -> Text
```

### `Lurk.i18n` — Pluralization

Explicit, type-safe pluralization. No complex rules — the programmer defines the forms, the framework picks the right one:

```haskell
data PluralForm = Singular | Plural | Dual | Paucal

newtype Pluralizable = Pluralizable (Map PluralForm Text)

singular :: Text -> Pluralizable
plural   :: Text -> Pluralizable
dual     :: Text -> Pluralizable
paucal   :: Text -> Pluralizable

pluralize :: Int -> Pluralizable -> Text
```

Usage in templates:

```haskell
[lurk|
  <span>{{pluralize itemCount (singular "item" <> plural "items")}}</span>
|]
```

Why this works:
- **No magic** — Programmer decides forms, not the framework. No surprise singularization bugs.
- **Language-agnostic** — Japanese uses `Singular` always. Estonian/Arabic edge cases are the translator's problem.
- **Composable** — `Monoid` instance lets you combine forms: `singular "item" <> plural "items"`
- **Extensible** — Add `Dual`, `Paucal` constructors for languages that need them (Arabic, Hebrew, Polish)

### `Lurk.WebSocket` — Real-Time Communication

```haskell
wsHandler :: FromJSON msg => (msg -> Action ()) -> LurkApp ()
broadcast  :: ToJSON msg => msg -> ConnectionPool -> IO ()
sendTo     :: ToJSON msg => ConnectionId -> msg -> IO ()
```

### `Lurk.Cache` — Caching Layer

```haskell
cacheGet    :: CacheStore -> Text -> IO (Maybe a)
cacheSet    :: CacheStore -> Text -> Int -> a -> IO ()
cacheDelete :: CacheStore -> Text -> IO ()
cacheOr     :: CacheStore -> Text -> Int -> IO a -> IO a
```

### `Lurk.WASM` — Selective WASM Interactivity

Only interactive "leaf" blocks compiled via GHC WASM backend.
No Virtual DOM overhead. Faster than Next.js.

### `Lurk.Admin` — Auto-Generated Admin Dashboard

Reflect on `Locales/` and `Controller/` types to auto-generate a secure
admin dashboard. Surpass Laravel's Filament.

---

## Deployment & Performance

### Binary Stripping

Add `strip` step to reduce binary size from ~55MB to ~20MB.

### Remote Build Support

Optional remote builds on VPS for projects where VPS RAM > 4GB.

---

## Issues Found

### Critical

1. **Missing `wai-middleware-force-ssl` in `lurk.cabal`** — `App.hs:27` imports `Network.Wai.Middleware.ForceSSL` but `lurk.cabal` does not list it in `build-depends`. Will fail on clean `cabal build`.

2. **`?` replacement is global** — `QQ.hs:195` replaces ALL `?` characters with `__implicit_`, including inside string literals and comments. Should only replace `?` at identifier word boundaries.

### Cleanup

3. **Unused dependencies** — `lurk.cabal` library section lists `mtl`, `syb`, `network`, `cookie` but no module imports them.

4. **Empty `CHANGELOG.md`** — Should be populated or removed.
