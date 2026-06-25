# Lurk Analysis: Framework Comparison

## What Works Today

- **`[lurk|...|]` QQ** — Compile-time variable checking. A typo in `{userName}` is a build error, not a runtime blank.
- **`getPages allLanguages pathFn actionFn`** — Registering routes for all languages in one call.
- **`postActions`** — Same pattern for POST routes.
- **Session + CSRF middleware** — File-backed sessions with automatic CSRF validation on POST.
- **`Lurk.Form`** — Composable anti-abuse pipeline: honeypot, timing, MX verification, field length. Guards run in `Action` for session access. `withForm` orchestrates the pipeline.
- **`Lurk.Email.SMTP`** — Self-contained SMTP client (STARTTLS/SMTPS). Zero external email library dependencies.
- **`Lurk.Env`** — Opaque `Env` type with `getEnv`/`requireEnv`/`hasEnv`. Loads `.env` at startup.
- **`lurk deploy`** — Full deployment pipeline: build → package → transfer → activate. SSH, Docker, and Shell providers via `DeployProvider` typeclass. `--init` generates CI/CD config.
- **`lurk run` / `lurk build` / `lurk kill`** — Dev server, build, and port management CLI commands.

## VS Code Extension (Implemented)

- **QQ delimiter highlighting** — `[lurk|`, `|]`, `(lurk|`, `|)` each highlighted as single tokens.
- **Nesting levels** — 3-level depth via recursive grammar: Level 1 `[lurk|]` → Level 2 `(lurk|)` → Level 3 `[lurk|]`.
- **`{{ }}` interpolation** — Haskell highlighting inside QQ blocks, including inside HTML attributes (`href="{{...}}"`, `class='{{...}}'`).
- **`?variable`** — Implicit parameters highlighted as `variable.language.implicit.haskell`.
- **`forEach`/`forEachWithIndex`** — Keywords highlighted as `keyword.control.then.haskell`.
- **Lurk snippets** — `lurk`, `lurki`, `fe`, `fei`, `fmap` triggers.

---

## Framework Comparison

### Core DX

| Feature               | Lurk              | Laravel           | Next.js           | Django            | Rails             |
|-----------------------|-------------------|-------------------|-------------------|-------------------|-------------------|
| Language              | Haskell           | PHP               | TypeScript        | Python            | Ruby              |
| Type safety           | Compile-time      | Runtime           | Compile-time (TS) | Runtime           | Runtime           |
| Template syntax       | `[lurk\|...\|]` QQ | Blade `{{ }}`     | JSX `{}`          | Jinja `{{ }}`     | ERB `<%= %>`      |
| Template control flow | `@if`/`@forEach`  | `@if`/`@foreach`  | `{condition && }` | `{% if %}`        | `<% if %>`        |
| Component model       | Native functions  | Blade components  | React components  | Template inheritance | Partials       |
| Variable interpolation| `{{expr}}`        | `{{ $var }}`      | `{var}`           | `{{ var }}`       | `<%= var %>`      |
| CSS/JS in templates   | Just works        | Just works        | Just works        | Just works        | Just works        |

### Configuration & Environment

| Feature            | Lurk              | Laravel                  | Next.js                  | Django         | Rails                  |
|--------------------|-------------------|--------------------------|--------------------------|----------------|------------------------|
| Config system      | `Lurk.Env`        | `config/*.php` + `.env`  | `next.config.js` + `.env`| `settings.py`  | `config/` + `.env`     |
| Env loading        | `.env` + process  | `.env` + `config()`      | `.env.local`             | `os.environ`   | `.env` + `credentials` |
| Type-safe config   | `getEnv`/`requireEnv` | Runtime `config()`    | Runtime `process.env`    | Runtime `os.getenv` | Runtime `ENV[]`    |
| Secrets management | `.env` file       | `.env` + Vault           | Varies by hosting        | `secrets.py`   | `credentials.yml`      |

### Routing

| Feature               | Lurk                                      | Laravel                  | Next.js           | Django         | Rails             |
|-----------------------|-------------------------------------------|--------------------------|-------------------|----------------|-------------------|
| Route definition       | `Router.hs` (explicit)                    | `routes/web.php`         | File-based (`app/`)| `urls.py`      | `config/routes.rb`|
| Multi-language routing | `getPages allLanguages pathFn actionFn`   | Manual per-route         | `next-intl` plugin| `i18n_patterns`| `I18n` gem        |
| Route groups           | Not yet                                   | `Route::middleware(...)` | Not needed        | `include()`    | `scope()`         |
| Named routes           | Not yet                                   | `route('home')`          | Not needed        | `reverse()`    | `root_path`       |
| POST route helper      | `postActions`                             | `Route::post()`          | API routes        | `path()`       | `post()`          |

### Forms & Validation

| Feature            | Lurk                                      | Laravel            | Next.js           | Django         | Rails             |
|--------------------|-------------------------------------------|--------------------|-------------------|----------------|-------------------|
| Form handling      | `Lurk.Form` (composable pipeline)         | `FormRequest`      | Server Actions    | `forms.py`     | `form_for`        |
| Anti-abuse         | Guard pipeline: honeypot + timing + MX + length | Manual       | Manual            | Manual         | Manual            |
| CSRF protection    | Automatic (WAI middleware)                | Token in forms     | Manual            | Token middleware| `authenticity_token` |
| Validation         | Project-level                             | `Rule::` classes   | Zod/JSR schemas   | `clean()` methods | Validations DSL |
| Email abstraction  | `Lurk.Email.SMTP` (self-contained)        | `Mail::to()`       | Nodemailer/Resend | `send_mail`    | `ActionMailer`    |

### Security

| Feature            | Lurk                    | Laravel            | Next.js           | Django         | Rails             |
|--------------------|-------------------------|--------------------|-------------------|----------------|-------------------|
| XSS prevention     | `{{ }}` auto-escape     | `{{ }}` auto-escape| JSX auto-escape   | `{{ }}` auto-escape | `<%= %>` auto-escape |
| CSRF               | Automatic middleware    | Token verification | Manual            | Middleware     | Middleware        |
| Session management | File-backed (TVar)      | File/Redis/DB      | Cookie-based      | Cookie/DB/Cache| Cookie/DB/Cache   |
| Auth primitives    | `Lurk.Auth` (planned)   | Built-in guards    | NextAuth.js       | `django.contrib.auth` | Devise     |
| Bot protection     | `Lurk.Form` guards      | Manual             | Manual            | Manual         | Manual            |
| Rate limiting      | Not yet                 | `ThrottleRequests` | Not built-in      | `ratelimit`    | `rack-attack`     |

### Database & ORM

| Feature      | Lurk              | Laravel      | Next.js           | Django         | Rails             |
|--------------|-------------------|--------------|-------------------|----------------|-------------------|
| ORM          | `Lurk.DB` (planned)| Eloquent     | Prisma/Drizzle    | Django ORM     | ActiveRecord      |
| Migrations   | Not yet           | `artisan make:migration` | Prisma migrate | `makemigrations` | `rails db:migrate` |
| Type safety  | Haskell type = schema | Runtime  | TypeScript types  | Runtime        | Runtime           |
| Query builder| Not yet           | Fluent       | Prisma client     | QuerySet       | Arel              |

### Deployment

| Feature      | Lurk                      | Laravel                  | Next.js           | Django         | Rails             |
|--------------|---------------------------|--------------------------|-------------------|----------------|-------------------|
| Deployment   | `lurk deploy` (SSH/Docker/Shell) | Forge/Vapor/Envoyer | Vercel/Netlify    | Heroku/Railway | Heroku/Render     |
| Build output | Single binary             | PHP files                | Node.js bundle    | Python package | Ruby gem          |
| Binary size  | ~55MB (strippable ~20MB)  | N/A                      | N/A               | N/A            | N/A               |
| Cold start   | Instant (native binary)   | Fast (opcache)           | Cold (Node.js)    | Moderate       | Moderate          |
| Process model| Single binary             | PHP-FPM                  | Node.js event loop| Gunicorn       | Puma/Unicorn      |

### CLI & Scaffolding

| Feature         | Lurk              | Laravel            | Next.js           | Django         | Rails             |
|-----------------|-------------------|--------------------|-------------------|----------------|-------------------|
| CLI             | `lurk`            | `php artisan`      | `create-next-app` | `manage.py`    | `rails`           |
| Code generators | `lurk create page`| `make:view`, etc.  | `create-next-app` | `startapp`     | `generate`        |
| Scaffolding     | `lurk init`       | `laravel new`      | `create-next-app` | `startproject` | `rails new`       |
| IDE support     | GHC (HLS)         | PHPStorm/VS Code   | VS Code           | VS Code        | VS Code           |

### Performance

| Feature      | Lurk              | Laravel      | Next.js       | Django         | Rails           |
|--------------|-------------------|--------------|---------------|----------------|-----------------|
| Runtime      | Native binary     | PHP-FPM/8.3  | Node.js (V8)  | CPython        | CRuby           |
| Rendering    | Server-side       | Server-side  | SSR + CSR     | Server-side    | Server-side     |
| Memory       | ~10MB             | ~30MB        | ~50MB         | ~30MB          | ~40MB           |
| Concurrency  | Green threads (GHC)| PHP-FPM     | Event loop    | Gunicorn       | Puma threads    |
| Caching      | `Lurk.Cache` (planned) | Redis/File | Edge/CDN     | Redis/Memcached| Redis/Memcached |

### Real-Time

| Feature              | Lurk              | Laravel            | Next.js     | Django         | Rails           |
|----------------------|-------------------|--------------------|-------------|----------------|-----------------|
| WebSockets           | `Lurk.WebSocket` (planned) | Laravel WebSockets | Socket.io | Django Channels | Action Cable |
| Server-Sent Events   | Not yet           | Not built-in       | Not built-in| Not built-in   | Not built-in    |

### i18n

| Feature         | Lurk                    | Laravel            | Next.js           | Django             | Rails           |
|-----------------|-------------------------|--------------------|-------------------|--------------------|-----------------|
| Multi-language  | enum + path routing     | `Lang::` facade    | `next-intl`       | `LocaleMiddleware` | `I18n` gem      |
| Pluralization   | `Pluralizable` ADT      | `Str::plural()`    | Manual            | `blocktranslate`   | `pluralize`     |
| Date formatting | `Lurk.i18n` (planned)   | `Carbon::`         | `Intl.DateTimeFormat` | `django.utils formats` | `l10n`    |
| Currency        | `Lurk.i18n` (planned)   | `Number::format`   | `Intl.NumberFormat` | Manual          | `Money` gem     |



---

## Comparison Rating (★ = 1, ★★★★★ = 5)

### Core DX

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Type safety         | ★★★★★| ★★      | ★★★★    | ★★     | ★★    |
| Template safety     | ★★★★★| ★★★★★   | ★★★★★   | ★★★★   | ★★★★  |
| Learning curve      | ★★   | ★★★★    | ★★★★★   | ★★★★★  | ★★★★  |
| Ecosystem           | ★★   | ★★★★★   | ★★★★★   | ★★★★   | ★★★★  |
| Community           | ★    | ★★★★★   | ★★★★★   | ★★★★★  | ★★★★  |

**Why the bests are the best:** Laravel/Next.js/Django have massive ecosystems because PHP/JS/Python have millions of devs. Community compounds: more users → more packages → more users.

**Our gap:** Haskell has ~200k developers vs millions for PHP/JS/Python. Small ecosystem, small community.

**Mitigation:** We don't compete on ecosystem size. We compete on what mass-market frameworks can never give: compile-time guarantees. Target teams that have been burned by production runtime errors, not teams that need 10,000 packages.

### Configuration & Environment

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Type-safe config    | ★★★★★| ★★      | ★★      | ★★     | ★★    |
| Secrets management  | ★★★  | ★★★★★   | ★★★     | ★★★    | ★★★★  |
| Simplicity          | ★★★★★| ★★★★    | ★★★     | ★★★    | ★★★★  |

**Why the bests are the best:** Laravel has `.env` + `config()` with caching, Vault integration, and encrypted env files. Rails has `credentials.yml` (encrypted, version-controlled).

**Our gap:** `.env` file only. No encrypted secrets, no Vault integration, no per-environment config beyond env vars.

**Mitigation:** `Lurk.EncryptedEnv` — encrypted YAML (like Rails credentials) with a master key. Vault integration can wait.

### Routing

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Multi-language      | ★★★★★| ★★★     | ★★★★    | ★★★★   | ★★★★  |
| Explicitness        | ★★★★★| ★★★★    | ★★★★★   | ★★★    | ★★★   |
| Named routes        | ★★★★★| ★★★★★   | ★★★★★   | ★★★★★  | ★★★★★ |

**Why the bests are the best:** Laravel `route('home')`, Django `reverse()`, Rails `root_path` — named routes eliminate hardcoded URLs. Refactor a URL in one place, all links update.

**Our gap:** None. `Paths.hs` defines paths (routes) as functions instead of string keys. Type-safe, multi-language, compile-time checked.

### Forms & Validation

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Anti-abuse built-in | ★★★★★| ★★      | ★★      | ★★     | ★★    |
| CSRF                | ★★★★★| ★★★★    | ★★      | ★★★★   | ★★★★  |
| Validation DSL      | ★★★  | ★★★★★   | ★★★★★   | ★★★★   | ★★★★  |

**Why the bests are the best:** Laravel `Rule::required()->email()->max(255)` — declarative, chainable, self-documenting. Zod in Next.js does the same with TypeScript inference.

**Our gap:** No validation DSL. `Lurk.Form` handles anti-abuse; field validation is manual `case`/`unless` chains.

**Mitigation:** `Lurk.Validate` — composable validator: `require "name" |> maxLength 200 |> isEmail`. Returns `Either [Text] FormData`. We provide primitives, projects define rules. Haskell types make invalid states unrepresentable.

### Security

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| XSS prevention      | ★★★★★| ★★★★★   | ★★★★★   | ★★★★★  | ★★★★★ |
| CSRF automatic      | ★★★★★| ★★★★    | ★★      | ★★★★   | ★★★★  |
| Auth primitives     | ★★★  | ★★★★★   | ★★★★    | ★★★★★  | ★★★★★ |
| Bot protection      | ★★★★★| ★★      | ★★      | ★★     | ★★    |

**Why the bests are the best:** Laravel has guards, policies, gates, Sanctum, Fortify — a complete auth ecosystem. Django has `contrib.auth` with groups, permissions, and a built-in admin.

**Our gap:** Raw sessions. No login, no roles, no permissions. Every app builds auth from scratch.

**Mitigation:** `Lurk.Auth` — `login`, `logout`, `currentUser`, `requireAuth`, `requireRole`. Build on existing sessions + CSRF. Minimal core; let packages add OAuth, 2FA, etc.

### Database & ORM

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Type safety         | ★★★★★| ★★      | ★★★★    | ★★     | ★★    |
| ORM maturity        | ★★   | ★★★★★   | ★★★★    | ★★★★★  | ★★★★★ |
| Migrations          | ★★   | ★★★★★   | ★★★★    | ★★★★★  | ★★★★★ |

**Why the bests are the best:** Eloquent, ActiveRecord, Django ORM — decades of refinement. Migrations, relations, scopes, eager loading, soft deletes.

**Our gap:** Nothing. No ORM, no migrations, no query builder.

**Mitigation:** Hardest gap. Three options: (1) `opaleye` / `squeal` — existing typed PG libraries, steep learning curve. (2) Code-gen from Haskell types. (3) Thin `Lurk.DB` over raw SQL with type-safe parameter binding. We start with (3), iterate toward (2).

### Deployment

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Cold start          | ★★★★★| ★★★★    | ★★      | ★★★    | ★★★   |
| Memory footprint    | ★★★★★| ★★★     | ★★      | ★★★    | ★★★   |
| Build output        | ★★★★★| ★★★★    | ★★★     | ★★★    | ★★★   |
| Deployment ease     | ★★★★ | ★★★★★   | ★★★★★   | ★★★★   | ★★★★  |

**Why the bests are the best:** Laravel Forge/Vapor — one-click deploy. Next.js on Vercel — zero config. Django on Heroku — `git push heroku main`.

**Our gap:** `lurk deploy` works but requires SSH setup, systemd config, `lurk.yaml`. No one-click experience.

**Mitigation:** `lurk deploy --target digitalocean` / `--target hetzner` — provision a VPS, install deps, deploy in one command. The binary advantage (no runtime deps) makes this feasible.

### CLI & Scaffolding

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| CLI power           | ★★★★ | ★★★★★   | ★★★★    | ★★★★   | ★★★★★ |
| Code generators     | ★★★  | ★★★★★   | ★★★★    | ★★★★   | ★★★★  |
| IDE support         | ★★★★ | ★★★★★   | ★★★★★   | ★★★★★  | ★★★★★ |

**Why the bests are the best:** `artisan make:view`, `rails generate controller`, `django-admin startapp` — generate boilerplate with one command. Laravel has 50+ generators.

**Our gap:** No `lurk create` commands. Manual file creation + manual `.cabal` updates.

**Mitigation:** `lurk create page name` — generates `View/Name.hs`, `Locale/Name.hs`, updates `Router.hs`, registers in `.cabal`. Medium effort, high daily-use impact.

### Performance

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Memory              | ★★★★★| ★★★     | ★★      | ★★★    | ★★★   |
| Concurrency         | ★★★★★| ★★★★    | ★★★★★   | ★★★★   | ★★★★  |
| Rendering speed     | ★★★★★| ★★★★    | ★★★★    | ★★★    | ★★★   |
| Caching             | ★★★  | ★★★★★   | ★★★★★   | ★★★★★  | ★★★★★ |

**Why the bests are the best:** Laravel has Redis, file, and database caching with `Cache::remember()`. Next.js has edge caching, ISR, and CDN integration.

**Our gap:** No caching layer. Every request hits the full stack.

**Mitigation:** `Lurk.Cache` — in-memory (TVar) + optional Redis backend. `cacheGet`/`cacheSet`/`cacheOr`. Start with TVar for single-binary simplicity, add Redis as a package.

### i18n

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Type-safe i18n      | ★★★★★| ★★      | ★★      | ★★     | ★★    |
| Multi-language      | ★★★★★| ★★★★    | ★★★★    | ★★★★   | ★★★★  |
| Pluralization       | ★★★★★| ★★★★    | ★★★     | ★★★★   | ★★★★  |

**Why the bests are the best:** Laravel has `Str::plural()`, `trans_choice()`, locale-aware formatting. Django has `blocktranslate` with plural support.

**Our gap:** No date/currency formatting. No locale-aware number/date display. The `Pluralizable` ADT is designed but not shipped.

**Mitigation:** `Lurk.i18n` with `formatDate`, `formatCurrency`, `pluralize`. Use `Data.Text.ICU` for locale-aware formatting.

### Overall Summary

| Criteria            | Lurk | Laravel | Next.js | Django | Rails |
|---------------------|------|---------|---------|--------|-------|
| Best for            | Performance, Type safety, Security | Full-stack, Ecosystem | Frontend, DX | Python devs, Admin | Startups, Convention |
| Worst for           | Learning curve, Ecosystem | Type safety | Server resources | Performance | Performance |
| Most asked feature  | Auth, DB, CLI | Email, Forms | Deployment | Auth, ORM | Auth, CLI |
| Easiest to start    | ★★   | ★★★★    | ★★★★★   | ★★★★★  | ★★★★  |
| Best long-term      | ★★★★★| ★★★★    | ★★★     | ★★★★   | ★★★★  |

---

## Lurk's Competitive Advantages

1. **Compile-time safety** — Template variables, routes, and config are checked at build time. Laravel, Django, and Rails catch errors at runtime.

2. **Native binary deployment** — Single binary, no runtime dependencies. Next.js needs Node.js, Laravel needs PHP-FPM, Django needs Python.

3. **Cold start** — Instant. No interpreter startup, no opcode cache warmup, no JVM bootstrap.

4. **Memory** — ~10MB vs 30-50MB for other frameworks. Can run on cheaper servers.

5. **Type-safe i18n** — Missing translations are compile errors. Laravel/Django discover missing strings at runtime.

6. **Security by default** — CSRF is automatic, sessions are file-backed, config is opaque. No "forgot to add CSRF token" bugs.

7. **Composable anti-abuse pipeline** — `Lurk.Form` provides honeypot, timing, MX, and field length guards as composable `FormGuard` values. No other framework ships this.

8. **Self-contained SMTP** — `Lurk.Email.SMTP` handles STARTTLS/SMTPS with zero external email library dependencies. No need for PHPMailer, Nodemailer, or similar.

---

## Lurk's Gaps (vs Competitors)

1. **No CLI scaffolding** — Laravel has `artisan make:*`, Django has `startapp`. Lurk requires manual file creation. (Planned: `lurk create page`)

2. **No built-in auth** — Laravel has guards, Django has `auth`. Lurk has raw sessions. (Planned: `Lurk.Auth`)

3. **No database layer** — Laravel has Eloquent, Django has ORM. Lurk has nothing. (Planned: `Lurk.DB`, very hard)

4. **Haskell learning curve** — The target audience (PHP/JS devs) needs to learn Haskell. This is the biggest barrier.

5. **No rate limiting** — Laravel has `ThrottleRequests`. Lurk has nothing built-in. (Planned)

6. **No caching layer** — Laravel has Redis/file caching. Lurk has nothing. (Planned: `Lurk.Cache`)

---

## Priority: Close the Gaps

| #    | What               | Effort | Impact | Status | Why                                       |
| ---- | ------------------ | ------ | ------ | ------ | ----------------------------------------- |
| 5    | `Lurk.Cloudflare`  | Medium | High   | OPEN   | Turnstile still under development         |
| 6    | `Lurk.Auth`        | Medium | High   | OPEN   | Every app needs auth                      |
| 7    | `lurk create page` | High   | High   | OPEN   | CLI scaffolding, highest long-term impact |
| 8    | `Lurk.DB`          | High+  | High+  | OPEN   | Laravel killer, but massive effort        |
| 9    | `Lurk.Cache`       | Medium | Medium | OPEN   | Redis/file caching layer                  |
| 10   | Rate limiting      | Low    | Medium | OPEN   | ThrottleRequests equivalent               |
