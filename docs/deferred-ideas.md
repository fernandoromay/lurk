# Deferred Ideas

Ideas evaluated and intentionally deferred. May be revisited if needs change.

---

## Global State Redesign (ReaderT AppCtx)

**Status:** Deferred — not needed
**Originally proposed:** Eliminate `unsafePerformIO` globals
**What exists today:** `formBodyCache` (Session), `lockMap` (Log), `storeKey` (Session)
**Why deferred:** Process isolation handles multi-tenant. Each VPS / each deployment is its own process.
**When to revisit:** If a single process needs multiple independent configs (e.g., testing framework, multi-domain with different session backends).

---

## lockMap Cleanup

**Status:** Accepted — not a real problem
**Problem:** `lockMap` grows monotonically by distinct log file paths
**Why accepted:** Bounded by design (<10 entries for most apps, ~500 bytes). Deleting after use breaks the mutex.
**When to revisit:** If someone generates log files with unique names per request (misuse scenario).

---

## Locale Modules — Pointfree Views

**Status:** Deferred — not worth the churn
**Originally proposed:** Change locale functions to use `?lang` implicit param for pointfree style
**Tradeoff:** Changes 33 locale functions. Benefit is purely aesthetic. Couples locale layer to implicit params mechanism.
**When to revisit:** Never. The 1 `?lang` mention per controller body is acceptable.

---

## Page / Route ADT

**Status:** Deferred — incompatible with Lurk's philosophy
**Originally proposed:** Type-safe route ADT (`data Page = Home | Pricing | ...`) with compile-time exhaustiveness checking
**Why deferred:** Incompatible with Lurk's philosophy. Looking for a compatible solution.
**When to revisit:** When a compatible approach is found.
