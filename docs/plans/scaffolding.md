# Plan: Lurk Scaffolding Commands

## Overview

Add `lurk add <type>` subcommands to scaffold common project files. Each command generates boilerplate following Lurk's established patterns (locale + view + controller + paths).

## Commands

### 1. `lurk add page [name]`

Creates a new static page: locale, view, controller action, path entry.

**Prompt flow:**
1. No name? Ask for name → PascalCase for module/file, camelCase for action/path
2. Ask subdir or root (only if non-standard subdir like Web/ exists — scan for capitalized dirs at root excluding common non-src dirs)
3. Ask which controller to add the action to (scan `Controller/` dir)

**Files created:**
```
Locale/<Name>.hs          -- data <Name>Locale + locale :: Language -> <Name>Locale
View/<Name>.hs            -- <name>View :: ViewCtx Language => <Name>Locale -> Html + defaultLayout seo [lurk|...|]
```

**Files modified:**
```
Controller/<Ctrl>.hs      -- add import + action: <name>Action = render $ <name>View (<Name>.locale ?lang)
Paths.hs                  -- add <name>Path :: Language -> Text with all languages + "" fallback
Router.hs                 -- add get <name>Path <name>Action
```

**Template content:**

`Locale/<Name>.hs`:
```haskell
module Locale.<Name> where

import Locale.Prelude

data <Name>Locale = <Name>Locale
    { seo :: SEO
    -- TODO: add fields
    }

locale :: Language -> <Name>Locale
locale _ = <Name>Locale
    { seo = defaultSEO
        { title = "TODO"
        , metaTitle = "TODO"
        , metaDescription = "TODO"
        , canonical = Just $ domain <> <name>Path EN
        }
    }
```

`View/<Name>.hs`:
```haskell
{-# LANGUAGE RecordWildCards #-}

module View.<Name> where

import View.Prelude
import View.Layout.Default
import Locale.<Name>

<name>View :: ViewCtx Language => <Name>Locale -> Html
<name>View <Name>Locale{..} = defaultLayout seo [lurk|
<main>
  <!-- TODO: add content -->
</main>
|]
```

**Controller injection:**
- Add `import View.<Name>` and `import Locale.<Name> qualified as <Name>`
- Add action after last action: `<name>Action :: (?lang :: Language) => Action ()\n<name>Action = render $ <name>View (<Name>.locale ?lang)`

**Paths injection:**
- Parse existing language patterns from any existing path function
- Generate pattern for each language with `""` default: `<name>Path EN = "/<name>/"\n<name>Path _ = "/<name>/"`
- Append to Paths.hs

**Router injection:**
- Add `get <name>Path <name>Action` before `notFound` line

**`.cabal` update:**
- Auto-run `updateCabalModules` (already exists) — no manual injection needed

---

### 2. `lurk add form [name]`

Creates a form POST endpoint with email notifications.

**Prompt flow:**
1. No name? Ask for name (allow camelCase)
2. Select a view/page this form belongs to (scan `View/` excluding `Partial/`, `Layout/`, `Email/`)
3. Ask subdir or root (same scan as page)
4. Ask which controller for the GET action (scan `Controller/`)

**Files created:**
```
Controller/Form.hs              -- if not exists; otherwise append to existing
View/Email/<Name>Notice.hs      -- admin notification email template
View/Email/<Name>Thanks.hs      -- user confirmation email template
Locale/Email/<Name>Notice.hs    -- admin email locale (minimal — no locale needed)
Locale/Email/<Name>Thanks.hs    -- user confirmation locale with locale
```

**Files modified:**
```
Controller/<Ctrl>.hs            -- add GET action with setFormLoadTime
Router.hs                       -- add post <view>Path <name>PostAction + get <view>Path <name>Action
```

**Template content:**

`Controller/Form.hs` (new or appended):
```haskell
module Controller.Form (<name>Action, <name>PostAction) where

import Lurk.Prelude
import Lurk.Form
import Lurk.Email.SMTP
import Lurk.Log (Logger(..), newLogger)
import Language
import View.<Page> qualified as <Page>
import Locale.<Page> qualified as <Page>
import View.Email.<Name>Thanks
import Locale.Email.<Name>Thanks qualified as <Thanks>

-- | Load SMTP configuration from environment
loadSmtpConfig :: IO (Maybe SmtpConfig)
loadSmtpConfig = do
    env <- getAppEnv
    let mHost = getEnv env "SMTP_HOST"
        mPort = getEnv env "SMTP_PORT"
        mUser = getEnv env "SMTP_USER"
        mPass = getEnv env "SMTP_PASS"
    case (mHost, mPort, mUser, mPass) of
        (Just h, Just p, Just u, Just pw) -> do
            let port = case reads (T.unpack p) of [(n, "")] -> n; _ -> 587
            pure $ Just SmtpConfig
                { smtpHost = h, smtpPort = port
                , smtpUsername = u, smtpPassword = pw
                , smtpFrom = u, smtpFromName = "TODO"
                }
        _ -> pure Nothing

loadAdminEmail :: IO (Maybe Text)
loadAdminEmail = do
    env <- getAppEnv
    pure $ getEnv env "ADMIN_EMAIL"

<name>Action :: (?lang :: Language) => Action ()
<name>Action = do
    setFormLoadTime
    render $ <page>View (<Page>.locale ?lang)

<name>PostAction :: (?lang :: Language) => Action ()
<name>PostAction = do
    ip <- fromMaybe "unknown" <$> clientIp
    fd <- validateForm
        (map ($ redirect "/404/")
            [ honeypot "b_website"
            , minSubmitTime 3
            , mxRecord "email"
            ]
        )

    let email = getParamDef "email" "" fd
    smtpLogger <- liftIO $ newLogger "logs/smtp.log"
    mConfig <- liftIO loadSmtpConfig
    mAdmin <- liftIO loadAdminEmail

    case (mConfig, mAdmin) of
        (Just config, Just adminEmail) -> liftIO $ do
            -- TODO: send admin notification email
            unless (T.null email) $ do
                let l = <Thanks>.locale ?lang
                    thanksFields = <Name>ThanksFields
                        { name = getParamDef "name" "" fd
                        , greeting = <Thanks>.greeting l
                        -- TODO: map remaining fields
                        }
                    body = renderHtml (nameThanks thanksFields)
                sendEmail config (Email email (<Thanks>.subject l) body) >>= pure
        _ -> liftIO $ logWarning smtpLogger "SMTP not configured" []

    redirect (thanksPath ?lang)
```

`View/Email/<Name>Thanks.hs`:
```haskell
{-# LANGUAGE RecordWildCards #-}
module View.Email.<Name>Thanks where

import Lurk.Prelude

data <Name>ThanksFields = <Name>ThanksFields
    { name :: Text
    -- TODO: add fields
    }

<name>Thanks :: <Name>ThanksFields -> Html
<name>Thanks <Name>ThanksFields{..} = [lurk|
<!DOCTYPE html>
<html><head></head>
<body style="font-family: Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto;">
  <h2>TODO</h2>
  <p>{{name}}</p>
</body></html>
|]
```

`Locale/Email/<Name>Thanks.hs`:
```haskell
module Locale.Email.<Name>Thanks where

import Locale.Prelude

data <Name>ThanksLocale = <Name>ThanksLocale
    { subject :: Text
    , greeting :: Text
    -- TODO: add fields
    }

locale :: Language -> <Name>ThanksLocale
locale _ = <Name>ThanksLocale
    { subject = "TODO"
    , greeting = "Hello"
    }
```

`View/Email/<Name>Notice.hs` — same pattern as Thanks but for admin (no `subject` in locale, fields are form data).

`Locale/Email/<Name>Notice.hs` — minimal, no `locale` needed (admin email is always same language).

**`.env.example` additions:**
```
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=your@email.com
SMTP_PASS=your-password
ADMIN_EMAIL=admin@example.com
```

---

### 3. `lurk add email [name]`

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

### 4. `lurk add legal [name]`

Creates a legal/content page (privacy policy, terms, cookie policy).

**Prompt flow:**
1. No name? Ask for name → PascalCase

**Files created:**
```
Locale/Legal/<Name>.hs   -- data <Name>Locale with raw Html content + locale
```

**Files modified:**
```
Controller/Static.hs     -- add import + action with LegalPage ADT pattern (if exists) or new action
Paths.hs                 -- add <name>Path
Router.hs                -- add get <name>Path <name>Action
```

**Template content:**

`Locale/Legal/<Name>.hs`:
```haskell
module Locale.Legal.<Name> where

import Locale.Prelude

data <Name>Locale = <Name>Locale
    { seo :: SEO
    , title :: Text
    , content :: Html
    }

locale :: Language -> <Name>Locale
locale _ = <Name>Locale
    { seo = defaultSEO
        { title = "TODO - <Name>"
        , metaTitle = "TODO"
        , metaDescription = "TODO"
        }
    , title = "TODO"
    , content = [lurk|
      <!-- TODO: add legal content -->
    |]
    }
```

**Controller pattern** — reuse existing `legalAction` with ADT if `Controller/Static.hs` already has it, otherwise add standalone action.

---

### 5. `lurk add error` — NOT scaffolded

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
