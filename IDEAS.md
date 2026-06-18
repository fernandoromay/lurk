# Lurk Ideas

## Built

- [x] `Lurk.Env` — opaque `Env` type with `getEnv`/`requireEnv`/`hasEnv`
- [x] `postActions` — multi-language POST route registration

---

## Easy (days)

### HTML Escaping Fix

`Lurk.Html.toHtml` only escapes `<`, `>`, and `&`. Does not escape `"`, `'`,
or backtick. XSS risk in attribute contexts:

```haskell
[lurk|<div class="{userInput}">|]
-- If userInput is: " onclick="alert(1)
-- Result: <div class=" " onclick="alert(1)">
```

**Fix:** Add `T.replace "\"" "&quot;"` and `T.replace "'" "&#39;"` to `toHtml`
in `Lurk.Html`. One-line change, real security impact.

### QQ Error Messages with Line Numbers

When a QQ expression fails to parse, the error gives no line number:
```
Parse error in LURK {} block: unexpected '<' expecting '}'
```

The QQ parser already uses megaparsec which tracks `SourcePos`. Exposing
line/column in the error output is straightforward. The template string
offset can be mapped back to a line number by counting newlines.

### `Lurk.Flash` — Flash Messages

One-time session data for success/error feedback:

```haskell
flashSuccess :: Text -> Action ()
flashError   :: Text -> Action ()
flashWarning :: Text -> Action ()
getFlash     :: Action (Maybe Flash)
```

Small, high-UX impact. Uses existing session system.

### Default Error Views

Ship `error404View` and `error500View` in a `Lurk.Views` module. Hardcoded
English strings. Projects that want custom branding override by defining
their own.

---

## Medium (weeks)

### `Lurk.Mail` — Email Abstraction

Current `Controller/Form.hs` has 140 lines of hand-rolled SMTP. Lurk should
own this:

```haskell
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

### `Lurk.Form` — Reusable Form Processing Pipeline

Every form handler repeats: honeypot, time-check, MX-verify, CSRF.
`Lurk.Form` eliminates that duplication:

```haskell
data FormConfig = FormConfig
    { fcStore         :: SessionStore
    , fcHoneypotField :: Text
    , fcMinSeconds    :: Int
    , fcRedirect      :: Text
    , fcHandler       :: [(Text,Text)] -> Action ()
    }

processForm :: FormConfig -> Action ()
```

Framework owns security. Project owns business logic.

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

The view decides what gets protected. Not invisible middleware.

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

### QQ Improvements (all at once)

The `[lurk|...|]` QQ needs several upgrades that should be designed and
implemented together since they all touch the same parser.

#### 1. `{{expr}}` syntax

Current `{haskell}` conflicts with CSS/JS `{}` blocks. Change to `{{expr}}`:

```haskell
[lurk|
<style>
.container { display: flex; }  -- currently breaks the QQ
</style>
<div class="{{cssClass}}">{{userName}}</div>
|]
```

Backwards incompatible but trivial to migrate (search-replace).

#### 2. Multi-line expressions

Currently expressions must be single-line. Allow multi-line inside `{{...}}`:

```haskell
[lurk|
<div>{{
    let x = 1
        y = 2
    in x + y
}}</div>
|]
```

The parser reads everything between `{{` and `}}` as Haskell, regardless
of newlines.

#### 3. Nested `[lurk|...|]` inside `{{...}}`

This is the key feature. It enables `forEach` and other higher-order
functions without creating a DSL:

```haskell
[lurk|
<ul>
{{forEach items (\item ->
    [lurk|<li>{{item.name}}</li>|]
)}}
</ul>
|]
```

The parser tracks bracket depth and recognizes `[lurk|` / `|]` as balanced
delimiters inside `{{...}}`. This means any Haskell function that takes
a `Text -> Html` callback works naturally:

```haskell
-- forEach with index
{{forEachWithIndex items (\i item ->
    [lurk|<li>{{i}}. {{item.name}}</li>|]
)}}

-- conditional rendering (just use Haskell)
{{if isLoggedIn then
    [lurk|<a href="/dashboard">Dashboard</a>|]
else
    [lurk|<a href="/login">Login</a>|]
}}

-- case expression
{{case userRole of
    Admin -> [lurk|<span>Admin</span>|]
    User  -> [lurk|<span>User</span>|]
    Guest -> [lurk|<span>Guest</span>|]
}}
```

No `@if`, no `@forEach`, no `@end`. Just Haskell. The QQ parser handles
the nesting, TH generates the right code.

#### Why no DSL?

Adding `@if`/`@forEach`/`@end` creates another language to learn.
Haskell already has `if`, `case`, `mapM_`, `foldMap`. The QQ should
let you USE Haskell, not replace it with a template language.

The only thing preventing this today is the parser can't handle nested
QQ blocks inside `{{...}}`. Fix the parser, and all of Haskell is available
inside templates — zero new syntax to learn.

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

### `lurk deploy`

Automates: build → SSH transfer → systemd restart. The `DeployProvider`
typeclass already exists. Needs CLI wiring.

### `Lurk.Language` Scaffolding

```
lurk init language EN ES KO
```

Generates `Language.hs` with enum, `allLanguages`, `langCode`, `langName`.

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

Pluralization, date formatting, currency formatting:

```haskell
t :: Language -> Text -> Int -> Text
t EN "item" 1 = "1 item"
t EN "item" n = show n <> " items"

formatDate :: Language -> UTCTime -> Text
formatCurrency :: Language -> Currency -> Text
```

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
