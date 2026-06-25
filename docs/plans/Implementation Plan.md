# Implementation Plan

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
    HIGH      │  1. Session UTCTime │  3. Global State    │
    LOCKING   │  2. Idle Timeout    │  4. Config System   │
              │                     │                     │
              ├─────────────────────┼─────────────────────┤
              │                     │                     │
    LOW       │  5. Log Append      │  7. Lurk.Auth       │
    LOCKING   │  6. SMTP Cert       │  8. Lang Detection  │
              │                     │                     │
              └─────────────────────┴─────────────────────┘
```

## Items

### 3. Global State
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

### 5. Log Append
**Locking:** LOW — standalone
**Easiness:** EASY — change one function

**Problem:** `writeLog` creates `.tmp` file, writes one entry, renames to target. Overwrites entire log file each time — only last entry survives.

**Fix:** Read existing content, append new entry, write back. Or use `appendFile` / `openFile AppendMode`.

**Files:** `Lurk/Log.hs` (lines 52-64)

---

### 6. SMTP Certificate Validation
**Locking:** LOW — standalone
**Easiness:** EASY — change one boolean

**Problem:** `settingDisableCertificateValidation = True` — disables TLS certificate verification by default. Insecure.

**Fix:** Add `smtpDisableCertValidation :: Bool` field to `SmtpConfig` (default `False`). Only disable when explicitly configured.

**Files:** `Lurk/Email/SMTP.hs` (line 64)

---

### 7. Lurk.Auth
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

**Depends on:** #1 (Session UTCTime), #2 (Idle Timeout), #4 (Config)

**Files:** New `Lurk/Auth.hs`

---

### 8. Language Detection & Fallback
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

**Depends on:** #1 (Session UTCTime), #2 (Idle Timeout)

**Files:** New `Lurk/Language/Detect.hs`

---

## Dependency Graph

```
#1 Session UTCTime ──┐
                     ├─→ #7 Lurk.Auth
#2 Idle Timeout ─────┤
                     ├─→ #8 Language Detection
#4 Config System ────┘
```

Items #3, #5, #6 are independent.
