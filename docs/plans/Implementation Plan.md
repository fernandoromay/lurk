# Important Fixes

## Prioritization Dimensions

| Dimension | What it means |
|-----------|---------------|
| **Locking** | Does this block other improvements? High = many features depend on it |
| **Easiness** | How hard to implement? Easy = hours, Medium = days, Hard = weeks |

## Priority Matrix

```
                        EASY                    HARD
              ┌─────────────────────┬─────────────────────┐
              │                     │                     │
    HIGH      │                     │  1. Global State    │
    LOCKING   │                     │                     │
              │                     │                     │
              ├─────────────────────┼─────────────────────┤
              │                     │                     │
    LOW       │  Log Improvements   │  3. Lurk.Auth       │
    LOCKING   │  2. SMTP Cert       │  4. Lang Detection  │
              │                     │                     │
              └─────────────────────┴─────────────────────┘
```

## Items

### 1. Global State
**Locking:** HIGH — scalability, multi-server deployments
**Easiness:** HARD — architectural redesign

**Problem:** `unsafePerformIO` global TVar refs in `Lurk.App` (`storeRef`, `envRef`) and `Lurk.CSRF` (`formBodyCache`). Single-server only, not safe for multiple app instances.

**Fix:** Thread `SessionStore` and `Env` through the app explicitly:
- `LurkApp` becomes `ReaderT AppCtx (ScottyM ())` 
- `Action` becomes `ReaderT AppCtx (ActionM ())`
- `AppCtx` record holds `SessionStore`, `Env`, etc.
- No more `unsafePerformIO`

**Files:** `Lurk/App.hs`, `Lurk/CSRF.hs`, all modules using `getStore`/`getAppEnv`

---

### 2. SMTP Certificate Validation
**Locking:** LOW — standalone
**Easiness:** EASY — change one boolean

**Problem:** `settingDisableCertificateValidation = True` — disables TLS certificate verification by default. Insecure.

**Fix:** Add `smtpDisableCertValidation :: Bool` field to `SmtpConfig` (default `False`). Only disable when explicitly configured.

**Files:** `Lurk/Email/SMTP.hs` (line 64)

---

### 3. Lurk.Auth
**Locking:** LOW — standalone feature
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

---

### 4. Language Detection & Fallback
**Locking:** LOW — standalone feature
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

