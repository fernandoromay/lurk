# Plan: Lurk Scaffolding Commands

## Overview

Add `lurk add <type>` subcommands to scaffold common project files. Each command generates boilerplate following Lurk's established patterns (locale + view + controller + paths).

## Commands

### `lurk add email [name]`

Standalone email template pair (without form scaffolding).

**Prompt flow:**

1. No name? Ask for name

**Files created:**
```
View/Email/<Name>.hs         -- data <Name>Fields + render function
Locale/Email/<Name>.hs       -- data <Name>Locale + locale
```

**No files modified** — email templates are standalone, no router/controller changes.

**Template:** Same as Form's email templates above.

---

### `lurk add error` — NOT scaffolded

Too simple. A single `View/Error.hs` with inline locale strings. Documentation in `LURK_CLI.md` or `docs/` suffices.

---

## Existing infrastructure reuse

| Existing function | Used by |
|---|---|
| `normalizeName` | page, form, email, legal (name normalization) |
| `capitalize` | page, legal (PascalCase module names) |
| `promptChoice` | page, form (select controller, target dir) |
| `promptCustomDir` | page, form (custom subdir) |
| `promptProjectName` → `promptName` | all (name input) |
| `discoverModules` / `updateCabalModules` | all (auto-update .cabal) |
| `prefixHsFile` / `applyModulePrefix` | page, form (if using subdir prefix) |

## New helpers needed

```haskell
-- | Prompt for a name (PascalCase for modules, camelCase for actions)
promptName :: String -> IO String

-- | Scan Controller/ dir for available controllers
scanControllers :: IO [String]

-- | Scan View/ dir for available views (excluding Partial/, Layout/, Email/)
scanViews :: IO [String]

-- | Detect non-standard source subdirs (capitalized, not common dirs)
scanSubdirs :: IO [String]

-- | Inject import line after module declaration in a .hs file
injectImport :: FilePath -> T.Text -> IO ()

-- | Inject code before a marker line (e.g., before "notFound" in Router)
injectBefore :: FilePath -> T.Text -> T.Text -> IO ()

-- | Inject path function before closing of Paths.hs
injectPath :: FilePath -> T.Text -> IO ()
```

## CLI wiring

In `main`:
```haskell
["add", "page", name]   -> addPage name
["add", "page"]         -> addPage ""
["add", "form", name]   -> addForm name
["add", "form"]         -> addForm ""
["add", "email", name]  -> addEmail name
["add", "email"]        -> addEmail ""
["add", "legal", name]  -> addLegal name
["add", "legal"]        -> addLegal ""
```

## Files modified (lurk CLI itself)

| File | Change |
|---|---|
| `cli/Main.hs` | Add `addPage`, `addForm`, `addEmail`, `addLegal` + helpers + CLI patterns |
| `lurk.cabal` | No changes needed (no new deps) |

## Files created (in user projects, by the scaffolds)

| Scaffold | Files created | Files modified |
|---|---|---|
| page | `Locale/<Name>.hs`, `View/<Name>.hs` | Controller, Paths, Router |
| form | `Controller/Form.hs` (or append), `View/Email/<Name>Notice.hs`, `View/Email/<Name>Thanks.hs`, `Locale/Email/<Name>Notice.hs`, `Locale/Email/<Name>Thanks.hs` | Controller (GET), Router |
| email | `View/Email/<Name>.hs`, `Locale/Email/<Name>.hs` | (none) |
| legal | `Locale/Legal/<Name>.hs` | Controller, Paths, Router |

## Open questions

1. **Paths localization**: Should `lurk add page` auto-generate localized path slugs (e.g., `/pricing/` → `/es/precios/`)? Or just use the same slug for all languages with `""` default? Current plan uses `""` default — user fills in localized variants manually.

2. **Form field scaffolding**: Should `lurk add form` ask for form field names and generate the `FormData` extraction code? Or leave as TODO? Current plan leaves as TODO.

3. **Legal ADT extension**: When adding a legal page, should it extend an existing `LegalPage` ADT in `Controller/Static.hs`? Or create standalone actions? Current plan handles both cases.

4. **Email admin locale**: The admin notice email (`<Name>Notice`) doesn't need a `locale` since it's always in the default language. Should we skip the locale file entirely and hardcode strings in the view? Current plan creates a minimal locale file for consistency.
