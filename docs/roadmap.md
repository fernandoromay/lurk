# Lurk Framework — Roadmap

## Prioritization Dimensions

| Dimension | What it means |
|-----------|---------------|
| **Blocking** | Does this block other improvements? High = many features depend on it |
| **Easiness** | How hard to implement? Easy = hours, Medium = days, Hard = weeks |

Items are sorted by: High blocking + Easy first, then High blocking + Hard, then Low blocking + Easy, then Low blocking + Hard.

---

## Checklist

### Security & Robustness
- [x] SMTP certificate validation — disable flag on by default (`Lurk/Email/SMTP.hs:64`)
- [x] Log append — `writeLog` overwrites file, only last entry survives (`Lurk/Log.hs`)
- [ ] Log per-path mutex — concurrent writes to same file lose entries (`Lurk/Log.hs`)
- [x] HTTP security headers — no X-Content-Type-Options, X-Frame-Options, etc. (`ServeStatic` middleware)
- [x] Default error views — `error404View` / `error500View` in `Lurk.Error`
- [ ] CSRF form body cache leak — orphaned entry on 403 path (`Lurk/CSRF.hs`)
- [x] XSS escaping — `toHtml` now escapes HTML entities

### Architecture
- [ ] Global state redesign — `unsafePerformIO` → `ReaderT AppCtx` (`Lurk/App.hs`, `Lurk/CSRF.hs`, `Lurk/Log.hs`)

### DX & Scaffolding
- [ ] `lurk add page [name]` — scaffold locale + view + controller + paths (designed in `scaffolding.md`)
- [ ] `lurk add form [name]` — scaffold form endpoint + email templates (designed in `scaffolding.md`)
- [ ] `lurk add email [name]` — scaffold email template pair (designed in `scaffolding.md`)
- [ ] `lurk add legal [name]` — scaffold legal content page (designed in `scaffolding.md`)

### Logging
- [ ] Log minimum level filtering — `LogLevel` in `Config`, `newLogger` filtering (designed in `log-improvements.md`)
- [ ] Export `LogLevel(..)` — currently not exported

### Features
- [ ] Language Detection & Fallback — cookie → Accept-Language → default (designed in `important-fixes.md`)
- [ ] `Lurk.Auth` — session-based login/logout/currentUser/requireAuth/requireRole (designed in `IDEAS.md`)
- [ ] Rate limiting — `ThrottleRequests` equivalent
- [ ] `Lurk.Cache` — in-memory (TVar) + optional Redis backend
- [ ] `Lurk.Validate` — composable field validation DSL (`require "name" |> maxLength 200 |> isEmail`)
- [ ] `Lurk.Opaque` — bot-proof email/phone rendering (designed in `IDEAS.md`)
- [ ] Path Parameters — dynamic URL segments for CMS-like content (`/:slug`)
- [x] REST HTTP methods — `delete`, `put`, `patch` wrappers
- [ ] Per-route middleware — apply auth/rate-limiting to specific routes
- [ ] `Lurk.i18n` — date formatting, currency formatting, pluralization (`Pluralizable` ADT)
- [ ] `Lurk.Cloudflare` Turnstile — CAPTCHA replacement (requires `http-client` dep)
- [ ] VS Code error diagnostics — unclosed QQ delimiters, empty `{{ }}`

### Database & ORM
- [ ] `Lurk.DB` — type-safe database layer (hardest gap, quarters of work)

### Real-Time
- [ ] `Lurk.WebSocket` — real-time communication
- [ ] `Lurk.WASM` — selective WASM interactivity

### Deployment
- [ ] Health check / post-deploy verification — `verify` method in `DeployProvider`
- [ ] Pre-deploy guardrails — optional `test_cmd` in `lurk.yaml`
- [ ] Blue-green deployment — symlink swap for zero downtime
- [ ] PaaS providers — Heroku/Railway/Render integration
- [ ] `lurk deploy --target digitalocean` — one-command VPS provision + deploy
- [ ] Remote build support — build on VPS for low-RAM dev machines

### Admin
- [ ] `Lurk.Admin` — auto-generated admin dashboard from `Locales/` and `Controller/` types

### Documentation
- [ ] CHANGELOG.md — fill before v1 release
- [ ] Update `LURK Analysis.md` — remove completed items, add new gaps
- [ ] Update `IDEAS.md` — correct `Lurk.Cloudflare` status (Turnstile still pending)
- [ ] Update `README.md` — add `Lurk.Log`, `Lurk.Cloudflare` to feature list
- [ ] Update `LURK_CLI.md` — add `lurk add` commands

---

## Priority Matrix

```
                        EASY                    HARD
              ┌─────────────────────┬─────────────────────┐
              │                     │                     │
    HIGH      │  1. SMTP Cert       │  3. Global State    │
    BLOCKING  │  2. Log Append      │     Redesign        │
              │                     │                     │
              ├─────────────────────┼─────────────────────┤
              │                     │                     │
    LOW       │  4. Security Hdrs   │  6. Lurk.Auth       │
    BLOCKING  │  5. Error Views     │  7. Language Detect │
              │  5b. Log Mutex      │  8. Lurk.DB         │
              │  5c. Log Level      │  9. Lurk.Cache      │
              │  5d. CHANGELOG      │ 10. Scaffolding     │
              │  5e. CSRF Cache     │                     │
              └─────────────────────┴─────────────────────┘
```

---

## Detailed Items

### ~~1. SMTP Certificate Validation~~ DONE
**Blocking:** LOW — standalone, no other feature depends on it  
**Easiness:** EASY — change one boolean

**Problem:** `settingDisableCertificateValidation = True` in `Lurk/Email/SMTP.hs:64`. All SMTP connections skip TLS verification by default. Insecure for production.

**Fix:** Extracted `sendEmailWith :: Bool -> SmtpConfig -> Email -> IO (Either EmailError ())` internal function. `sendEmail` calls it with `False` (validation ON). `sendEmailInsecure` calls it with `True` (validation OFF). `SmtpConfig` unchanged — no new fields.

**Files:** `Lurk/Email/SMTP.hs`

---

### ~~2. Log Append (Write Overwrite)~~ DONE
**Blocking:** LOW — standalone  
**Easiness:** EASY — change one function

**Problem:** `writeLog` in `Lurk/Log.hs:52-64` creates `.tmp` file, writes one entry, renames to target. Overwrites entire log file — only last entry survives.

**Fix:** `writeLog` now reads existing content before writing, appends new entry. `createDirectoryIfMissing` moved inside `writeLog` for standalone function calls.

**Files:** `Lurk/Log.hs`, `test/LogSpec.hs`

---

### 3. Global State Redesign
**Blocking:** HIGH — blocks multi-server deployments, testing, scalability  
**Easiness:** HARD — architectural redesign across multiple modules

**Problem:** `unsafePerformIO` global TVar refs in:
- `Lurk.App` — `storeRef`, `envRef`
- `Lurk.CSRF` — `formBodyCache`
- `Lurk.Log` — `lockMap`

Single-server only. Not safe for multiple instances. Hard to test.

**Fix:** Thread `SessionStore` and `Env` through the app explicitly:
- `LurkApp` becomes `ReaderT AppCtx (ScottyM ())`
- `Action` becomes `ReaderT AppCtx (ActionM ())`
- `AppCtx` record holds `SessionStore`, `Env`, etc.

**Files:** `Lurk/App.hs`, `Lurk/CSRF.hs`, `Lurk/Log.hs`, all modules using `getStore`/`getAppEnv`

**Note:** This is the hardest architectural change. Consider doing incrementally — start with one module, prove the pattern, then migrate others.

---

### ~~4. HTTP Security Headers~~ DONE
**Blocking:** LOW — standalone middleware  
**Easiness:** EASY — add middleware to `ServeStatic` or new `SecurityHeaders` middleware

**Problem:** No security headers by default. Missing:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 0` (modern recommendation: disable legacy XSS filter)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Content-Security-Policy` (needs project-specific configuration)
- `Strict-Transport-Security` (HSTS — only when HTTPS)

**Fix:** Added `Lurk.Routes.Security` module with `securityHeaders` (defaults) and `securityHeadersWith` (merge API). Defaults ship without CSP (project-specific). HSTS conditional on `LURK_ENV=production`. `SecurityHeaders` / `SecurityHeadersWith` constructors in `RouteOption`.

**Files:** `Lurk/Routes/Security.hs`, `Lurk/Routes.hs`, `test/SecuritySpec.hs`

---

### ~~5. Default Error Views~~ DONE
**Blocking:** LOW — standalone  
**Easiness:** EASY — hardcoded English strings

**Problem:** No `error404View` / `error500View`. Projects must create their own or show raw errors. No 500 exception catching — Scotty dumps source code in production.

**Fix:** Added `Lurk.Error` module with `error404View`, `error500View` (self-contained HTML), and `errorMiddleware` (WAI middleware that catches exceptions, renders 500 view, logs to stderr). `serverError` helper added to `Lurk.Prelude`. Middleware applied automatically in `runLurk`.

**Files:** `Lurk/Error.hs`, `Lurk/App.hs`, `Lurk/Prelude.hs`, `test/ErrorSpec.hs`

---

### 5b. Log Per-Path Mutex
**Blocking:** LOW — standalone  
**Easiness:** EASY — MVar-based locking

**Problem:** Two concurrent `writeLog` calls to the same file read the same existing content, then both write — one entry lost.

**Fix:** Per-file-path `MVar` mutex using a global `TVar (Map FilePath (MVar ()))`. Blocks concurrent threads writing to the same file.

**Files:** `Lurk/Log.hs`

**Design:** Fully designed in `docs/plans/log-improvements.md:19-121`. Implementation ready.

---

### 5c. Log Minimum Level Filtering
**Blocking:** LOW — standalone  
**Easiness:** EASY — add field to `Logger`, filter at construction

**Problem:** No way to suppress debug/info in production. All levels always write.

**Fix:** Add `minLogLevel :: LogLevel` to `Config`. Thread it through via global `logLevelRef` TVar. `newLogger` reads it and skips writes for levels below threshold.

**Files:** `Lurk/Log.hs`, `Lurk/App.hs`, `Lurk/Prelude.hs`, `Main.hs`

**Design:** Fully designed in `docs/plans/log-improvements.md:127-297`. Implementation ready.

---

### 5d. CSRF Form Body Cache Leak
**Blocking:** LOW — robustness, not security
**Easiness:** EASY — add cleanup on 403 path

**Problem:** `formBodyCache` in `Lurk/CSRF.hs` caches form body before validation. Normal path (`getCachedFormParams` in `Lurk/Form.hs`) removes entry. But CSRF failure (403) or abort before `validateForm` leaves orphaned entry in unbounded TVar.

**Fix:** Add `cleanupFormBody` call in the CSRF failure path (line 147 of `CSRF.hs`).

**Files:** `Lurk/CSRF.hs`

---

### 6. Language Detection & Fallback
**Blocking:** LOW — standalone feature  
**Easiness:** MEDIUM — detection logic

**Problem:** No automatic language detection. Users must use language-specific paths.

**Fix:** Detection priority:
1. Cookie/session (saved preference)
2. `Accept-Language` header
3. Default fallback (first enum value)

```haskell
detectLanguage :: (Enum lang, Bounded lang) => [lang] -> Action lang
```

**Files:** New `Lurk/Language/Detect.hs`

**Design:** Already documented in `docs/plans/important-fixes.md:78-93` and `docs/IDEAS.md:58-81`.

---

### 7. `Lurk.Auth`
**Blocking:** LOW — standalone feature. Not every app needs auth (marketing sites, blogs, APIs with external auth don't).  
**Easiness:** MEDIUM — builds on existing sessions

**Problem:** No authentication primitives. Every app builds from scratch.

**Fix:** Session-based auth primitives:
```haskell
login        :: SessionStore -> User -> Action ()
logout       :: SessionStore -> Action ()
currentUser  :: SessionStore -> Action (Maybe User)
requireAuth  :: SessionStore -> Action User
requireRole  :: SessionStore -> Role -> Action User
```

**Files:** New `Lurk/Auth.hs`

**Design:** Already documented in `docs/IDEAS.md:118-128` and `docs/plans/important-fixes.md:57-73`.

---

### 8. `Lurk.Cache`
**Blocking:** LOW — standalone feature  
**Easiness:** MEDIUM — TVar-based in-memory cache

**Problem:** No caching layer. Every request hits the full stack.

**Fix:** In-memory (TVar) + optional Redis backend:
```haskell
cacheGet    :: CacheStore -> Text -> IO (Maybe a)
cacheSet    :: CacheStore -> Text -> Int -> a -> IO ()
cacheDelete :: CacheStore -> Text -> IO ()
cacheOr     :: CacheStore -> Text -> Int -> IO a -> IO a
```

**Files:** New `Lurk/Cache.hs`

**Design:** Already described in `docs/IDEAS.md:245-252`.

---

### 9. Scaffolding (`lurk add`)
**Blocking:** LOW — DX improvement  
**Easiness:** MEDIUM — CLI code generation, file injection

**Problem:** No `lurk create` commands. Manual file creation + manual `.cabal` updates. Highest daily-use impact among DX improvements.

**Fix:** `lurk add page [name]`, `lurk add form [name]`, `lurk add email [name]`, `lurk add legal [name]`.

**Files:** `cli/Main.hs`

**Design:** Fully designed in `docs/plans/scaffolding.md`. Implementation ready.

---

### 10. `Lurk.DB`
**Blocking:** LOW — but massive gap vs competitors  
**Easiness:** HARD — quarters of work

**Problem:** No ORM, no migrations, no query builder. Laravel has Eloquent, Django has ORM.

**Fix:** Type-safe database layer. Start with thin `Lurk.DB` over raw SQL with type-safe parameter binding, iterate toward code-gen from Haskell types.

**Files:** New `Lurk/DB.hs`

**Design:** Already described in `docs/IDEAS.md:387-399`.

---

## Future / Post-v1

| Item | Effort | Status |
|------|--------|--------|
| Rate limiting | Low | Not designed |
| `Lurk.WebSocket` | High | Not designed |
| `Lurk.WASM` | Very High | Not designed |
| `Lurk.Admin` dashboard | Very High | Not designed |
| Path Parameters (CMS) | Medium | Partially designed in IDEAS.md |
| Per-route middleware | Medium | Partially designed in IDEAS.md |
| `Lurk.i18n` (pluralization, dates) | Medium | Partially designed in IDEAS.md |
| `Lurk.Cloudflare` Turnstile | Medium | Requires `http-client` dep |
| VS Code error diagnostics | Medium | Not designed |
| Subdomain routing | High | Fully designed in IDEAS.md |
| `Lurk.Email` HTTP providers | High | Not designed |
| `Lurk.Email.Inbound` | High | Not designed |
| Remote build support | Medium | Not designed |
| PaaS providers | Medium | Not designed |
| Blue-green deployment | Medium | Not designed |
| Health checks | Low | Not designed |
| Encrypted env | Medium | Not designed |

---

## Implementation Order (Recommended)

### Phase 1: Security & Robustness (v1 blockers)
1. ~~SMTP certificate validation~~
2. ~~Log append fix~~
3. Log per-path mutex
4. CSRF form body cache cleanup
5. ~~HTTP security headers~~
6. ~~Default error views~~

### Phase 2: DX & Scaffolding
7. `lurk add page`
8. `lurk add form`
9. `lurk add email` (optional)

### Phase 3: Logging Improvements
10. Export `LogLevel`
11. Log minimum level filtering
12. Logger global via `logLevelRef`

### Phase 4: Features
13. Language Detection & Fallback
14. `Lurk.Auth`
15. Rate limiting
16. `Lurk.Cache`
17. `Lurk.Validate`
18. CHANGELOG.md

### Phase 5: Architecture (optional, for multi-server)
19. Global state redesign (`ReaderT AppCtx`)

### Phase 6: Database (long-term)
20. `Lurk.DB`

---

## References

| Document | Status | Relevance |
|----------|--------|-----------|
| `docs/LURK Analysis.md` | Needs update | 95% accurate, mark completed items |
| `docs/IDEAS.md` | Needs update | Correct Cloudflare status (Turnstile pending) |
| `docs/plans/log-improvements.md` | Ready to implement | Design complete, code ready |
| `docs/plans/scaffolding.md` | Ready to implement | Design complete, code ready |
| `docs/plans/important-fixes.md` | Partially done | SMTP #2 (open), Auth #3 (open), Global State #1 (open) |
| `docs/plans/session.md` | DONE | Fully implemented |
| `README.md` | Needs update | Missing Lurk.Log, Lurk.Cloudflare |
| `LURK_CLI.md` | Needs update | Missing `lurk add` commands |
