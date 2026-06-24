# Lurk Ideas

---

## Easy (days)

### Default Error Views

Ship `error404View` and `error500View` in a `Lurk.View` module. Hardcoded
English strings. Projects that want custom branding override by defining
their own.

---

## Medium (weeks)

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

### `Lurk.Cloudflare` — Typed Cloudflare Headers (DONE)

Implemented header lookups:

```haskell
cfCountry     :: Action (Maybe Text)
cfContinent   :: Action (Maybe Text)
cfCity        :: Action (Maybe Text)
cfRegion      :: Action (Maybe Text)
cfTimezone    :: Action (Maybe Text)
cfASN         :: Action (Maybe Text)
cfBotScore    :: Action (Maybe Text)
cfBotVerified :: Action (Maybe Bool)
```

Pending — requires `http-client` dependency (also useful for AI tool integrations):

```haskell
turnstileVerify :: Text -> Text -> IO Bool  -- CAPTCHA replacement
```

### Language Detection & Fallback

Detect language via:
1. **Cookie/session** — Highest priority. User's saved preference persists across visits.
2. **Browser `Accept-Language` header** — Parse and match against available languages.
3. **Default fallback** — EN (first language in enum order).

```haskell
detectLanguage :: (Enum lang, Bounded lang) => [lang] -> Action lang
detectLanguage available = do
    -- 1. Check cookie/session for saved preference
    saved <- getCookie "lang_preference"
    case saved >>= parseLang of
        Just lang | lang `elem` available -> pure lang
        _ -> do
            -- 2. Parse Accept-Language header
            acceptLang <- lookupHeader "Accept-Language"
            let browserLang = parseAcceptLanguage acceptLang >>= matchLang available
            -- 3. Fallback to default
            pure $ fromMaybe (head available) browserLang
```

Use case: `notFoundAction` can render in the user's language without requiring a language-specific path. `HomePage` can redirect to the most used language if no cookie exists.

### VS Code Error Diagnostics for Lurk Blocks

Detect at edit time via Language Server or VS Code diagnostics API:
- Unclosed `{{` or `}}`
- Unclosed `[lurk|` or `(lurk|`
- Missing `|]` or `|)` terminators
- `{{ }}` with empty content
- Nested `[lurk|` without matching close

### Remote Build Support

Optional remote builds on VPS for projects where VPS RAM > 4GB.

---

## Hard (months)

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

### `Lurk.Auth` — Session-Based Authentication

Extend existing session system:

```haskell
login        :: SessionStore -> User -> Action ()
logout       :: SessionStore -> Action ()
currentUser  :: SessionStore -> Action (Maybe User)
requireAuth  :: SessionStore -> Action User
requireRole  :: SessionStore -> Role -> Action User
```

### `lurk create page` — CLI Scaffolding

```bash
lurk create page ViewName ControllerName
```

Generates `View/ViewName.hs`, `Locales/ViewName.hs`, creates or updates
`Controller/ControllerName.hs`, registers in `.cabal`.

Also: `lurk create view`, `lurk create controller`, `lurk create locale`.

### Page / Route ADT

Type-safe route ADT (`data Page = Home | Pricing | ...`) with compile-time
exhaustiveness checking and auto-generated localized path helpers.

> Differed due to incompatibility with Lurk's philosophy of previous propositions.

### Path Parameters (CMS Phase)

Dynamic URL segments for content-driven pages:

```haskell
-- Register a route with a path parameter
getPagesWith allLanguages (pagePath Blog <> "/:slug") blogPostAction

-- Extract typed parameters in handlers
slug <- param "slug"  -- Scotty already provides this

-- Future: typed parameter extraction
data BlogRoute = BlogRoute { slug :: Text }
blogRoute :: RouteParam BlogRoute
```

Needed for: blog posts, product variants, user profiles, any CMS-like content.
Build on top of Scotty's existing `param` function.

### Unified HTTP Method Wrappers — REST Methods

Add `delete`, `put`, `patch` for REST APIs (consolidate with existing `get`/`post`):

```haskell
delete :: (Enum lang, Bounded lang)
       => (lang -> Text) -> (lang -> Action ()) -> LurkApp
put :: (Enum lang, Bounded lang)
    => (lang -> Text) -> (lang -> Action ()) -> LurkApp
patch :: (Enum lang, Bounded lang)
      => (lang -> Text) -> (lang -> Action ()) -> LurkApp
```

### Per-Route Middleware (Auth Phase)

Apply middleware to specific routes instead of globally:

```haskell
-- Current: all middleware is global via routeSettings
routeSettings [ TrailingSlashes, ForceSSL, ServeStatic "public" ]

-- Future: per-route middleware
getPages allPages homePath homeAction
getPagesWith [authRequired] allPages adminPath adminAction
getPagesWith [rateLimited 100] allPages apiPath apiAction
```

Needed for: admin dashboards, API endpoints, any protected content.
Could also support route groups: `routeGroup [authRequired] $ do ...`

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

### Subdomain Routing

Route different subdomains or domains to independent sub-routers within a single project.

**URL structures** (how language appears in URL — SEO concern):
- Path-based: `/es/`, `/ko/` (preferred — no authority split)
- Subdomain: `es.domain.com` (splits authority)
- Domain/ccTLD: `domain.es`, `domain.ko` (splits authority)

**Note:** Subdomains and separate domains split domain authority, which is bad for SEO. Path-based is preferred for SEO-first projects. However, some use cases (multi-brand, regional sites) may require subdomains or separate domains.

**Language detection signals** (fallback when no URL signal — e.g., 404 pages, social networks):
- Cookie/Session: User's saved preference
- Accept-Language header: Browser's language preference
- IP/Geo: Language based on user's location
- User profile: Logged-in user's saved preference

Structure:

```
├── Router.hs          # Main site (www/domain.com)
├── Blog/
│   ├── Router.hs      # blog.domain.com
│   ├── Controller.hs
│   └── View.hs
├── Admin/
│   ├── Router.hs      # admin.domain.com
│   ├── Controller.hs
│   └── View.hs
└── Cms/
    ├── Router.hs      # cms.domain.com
    ├── Controller.hs
    └── View.hs
```

New `Lurk.Domain` middleware inspects `Host` header, sets `?subdomain`:

```haskell
-- Lurk.Domain
domainRouter :: (Text -> LurkApp) -> LurkApp
domainRouter dispatch = do
    -- Middleware checks Host header, dispatches to sub-router
    ...
```

Main router dispatches based on subdomain:

```haskell
router :: LurkApp
router = do
    routeSettings [TrailingSlashes, ForceSSL, ServeStatic "public"]
    
    domainRouter $ \case
        "blog"  -> blogRouter
        "admin" -> adminRouter
        "cms"   -> cmsRouter
        _       -> siteRouter

siteRouter :: LurkApp
siteRouter = do
    get homePath homeAction
    get pricingPath pricingAction
    ...

blogRouter :: LurkApp
blogRouter = do
    get "/" blogHomeAction
    get "/:slug" postAction
    ...
```

Each sub-router is a standalone `LurkApp` — no coupling between them. They can use different locales, different middleware, different sessions.

**Language per subdomain:** Each sub-router defines its own `?lang` scope independently:

```haskell
siteRouter :: LurkApp
siteRouter = do
    get homePath homeAction    -- ?lang = EN | ES | KO (path-based)

blogRouter :: LurkApp
blogRouter = do
    -- Language from subdomain, not path
    domainGet "es" "/" blogHomeActionES
    domainGet "en" "/" blogHomeActionEN

adminRouter :: LurkApp
adminRouter = do
    get "/" adminHomeAction  -- ?lang fixed to EN (or user preference)
```

Different language types (`Language` vs `BlogLanguage` vs fixed `EN`), different path functions, different resolution strategies — all independent.

**Alternative: Shared content across languages** — When all subdomains serve the same content in different languages, use `Router/` with one file per language:

```
├── Router.hs          # Dispatches based on domain/subdomain
├── Router/
│   ├── EN.hs          # English routes
│   ├── ES.hs          # Spanish routes
│   └── KO.hs          # Korean routes
```

```haskell
-- Router.hs
router :: LurkApp
router = do
    domainRouter $ \case
        "es"    -> ES.router
        "ko"    -> KO.router
        _       -> EN.router

-- Router/EN.hs
router :: LurkApp
router = do
    get "/" homeActionEN
    get "/pricing/" pricingActionEN
    ...

-- Router/ES.hs
router :: LurkApp
router = do
    get "/" homeActionES
    get "/precios/" pricingActionES
    ...
```

Each language router is independent — different paths, different views, different locale files. The root router just dispatches.

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

### `Lurk.WASM` — Selective WASM Interactivity

Only interactive "leaf" blocks compiled via GHC WASM backend.
No Virtual DOM overhead. Faster than Next.js.

### `Lurk.Admin` — Auto-Generated Admin Dashboard

Reflect on `Locales/` and `Controller/` types to auto-generate a secure
admin dashboard. Surpass Laravel's Filament.

---

## Optional

### Locale modules — For pointfree views

Currently, locale functions are explicit (`locale :: Language -> SomeLocale`). Views call them as `Home.locale ?lang`. This works but prevents pointfree style in views.

To enable `homeView (Home.locale)` in pointfree style, locale functions need `?lang`:

```haskell
-- Before:
locale :: Language -> HomeLocale
locale EN = HomeLocale {..}
locale ES = HomeLocale {..}
locale KO = HomeLocale {..}

-- After:
locale :: (?lang :: Language) => HomeLocale
locale = case ?lang of
    EN -> HomeLocale {..}
    ES -> HomeLocale {..}
    KO -> HomeLocale {..}
```

**Tradeoff:** This changes 33 locale functions. The benefit is purely aesthetic (pointfree style). The locale layer becomes coupled to the implicit params mechanism.

**Recommendation:** Skip this phase. Keep locale explicit. The 1 `?lang` mention per controller body (`Home.locale ?lang`) is acceptable.

---

## Issues Found

### Critical

1. **Missing `wai-middleware-force-ssl` in `lurk.cabal`** — `App.hs:27` imports `Network.Wai.Middleware.ForceSSL` but `lurk.cabal` does not list it in `build-depends`. Will fail on clean `cabal build`.

2. **`?` replacement is global** — `QQ.hs:195` replaces ALL `?` characters with `__implicit_`, including inside string literals and comments. Should only replace `?` at identifier word boundaries.

---

## Deployment & Performance

### Remote Build Support

Optional remote builds on VPS for projects where VPS RAM > 4GB.

---

## Lurk Deployment Roadmap & Ideas

### 1. Verification & Health Checks
Deployment isn't finished when the service restarts; it's finished when the app is actually serving traffic.
- **Post-Deployment Probe**: Implement a `verify :: p -> IO (Either DeployError ())` method in `DeployProvider`.
- **HTTP Health Check**: The CLI should hit a configured `/health` endpoint. If it doesn't return 200 OK within N seconds, trigger an automatic rollback.
- **Log Tailing**: Optionally stream the last 20 lines of the remote log if `activate` fails to give the dev immediate feedback.

### 2. Pre-Deployment Guardrails
Shift-left verification to prevent broken binaries from ever touching the server.
- **Test Integration**: Add an optional `test_cmd` to `lurk.yaml`. The pipeline should execute this (e.g., `cabal test`) and abort the deployment if tests fail.
- **Binary Validation**: For SSH, run a quick version check or `--version` command on the compiled binary before transfer to ensure it's compatible with the target architecture.

### 3. Broadening the Provider Ecosystem
Move beyond VPS and Containers into managed ecosystems.
- **PaaS Providers**: 
  - **Heroku/Railway/Render**: Implement providers that use their respective CLIs or APIs to trigger builds and deployments.
  - **Static Hosting**: A provider for S3/Cloudflare Pages/Netlify for purely static assets.
- **Cloud-Native**: 
  - **AWS ECS/Lambda**: Integration with AWS CLI for task updates.
  - **Google Cloud Run**: Direct integration for containerized serverless.

### 4. Advanced Release Strategies
Move from "Restart" to "Zero Downtime".
- **Blue-Green Deployment**: For SSH, deploy to a sibling directory and update a symbolic link to the new version instantly.
- **Canary Releases**: (Docker/K8s) Route a small percentage of traffic to the new version before full rollout.
- **Database Migrations**: Integrate a `migration_cmd` that runs *after* the binary is transferred but *before* the service is activated.

### 5. User Experience & Tooling
- **`lurk init`**: Generate a base `lurk.yaml` and add it to `.gitignore` automatically.
- **Interactive Setup**: A wizard-style `lurk setup` that tests SSH connectivity and prompts for the correct paths/service names.
- **Progress Visualization**: Replace standard output with a progress bar and colored status indicators for each pipeline step.

### 6. Free Tier Integration (Testing Ecosystem)
To test the full suite of Lurk providers without infrastructure costs:
- **Oracle Cloud (Always Free)**: Primary target for multi-node testing (24GB RAM).
- **Google Cloud Run (Serverless)**: Test the Docker provider without managing a cluster (2M req/mo free).
- **Play with K8s/Docker**: Fast, ephemeral labs for CI/CD pipeline validation.
- **GitHub Packages (GHCR)**: Free OCI registry for testing Docker pushes in CI.
