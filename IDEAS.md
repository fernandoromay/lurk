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
