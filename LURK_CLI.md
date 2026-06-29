# Lurk CLI Reference

The Lurk CLI is the official deployment and management tool for the Lurk web framework. It is designed to take a Haskell project from local development to a production environment with minimal friction, automating the build, transfer, and activation processes.

## 📦 Installation

Lurk is distributed as a standalone executable. Install it globally using Cabal:

```bash
cabal install exe:lurk
```

- **Linux/macOS**: Installs to `~/.cabal/bin/lurk`
- **Windows**: Installs to `%APPDATA%\cabal\bin\lurk.exe`

Make sure the install directory is in your `PATH`. Most Haskell setups (ghcup) do this automatically.

**Updating**:
```bash
cabal install exe:lurk --overwrite-policy=always 2>&1
```
This rebuilds and replaces the existing binary with the latest version.

---

## 🚀 Core Commands

### `lurk run`
**Purpose**: Local Development.
Use this when you are actively coding and want to test changes in real-time.

- **What it does**: 
  1. Loads environment variables from `.env` into the process.
  2. Scans your source directories for new Haskell modules and automatically updates the `.cabal` file to ensure they are compiled.
  3. Executes `cabal run --ghc-options=-v0` to reduce verbosity.

### `lurk build`
**Purpose**: Local Verification.
Use this to ensure your project compiles correctly without actually starting the server.

- **What it does**: Performs the same `.env` loading and `.cabal` module updates as `run`, then executes `cabal build --ghc-options=-v0` to reduce verbosity.

### `lurk deploy`
**Purpose**: Production Release.
The core engine of the framework. It executes a strictly ordered pipeline to ensure atomic deployments.

**The Deployment Pipeline**:
1. **Resolve**: Resolves environment variable placeholders (e.g., `${VAR}`) in the provider configuration.
2. **Setup**: Provisions the remote environment. For SSH, this means creating the target directory and writing the systemd service file.
3. **Validate**: Verifies that the destination is reachable and ready.
4. **Package**: Runs `cabal build --minimize` to create a production-ready binary. It then uses `cabal list-bin` to find the exact path of the resulting executable, removing any hardcoded path assumptions.
5. **Transfer**: Securely uploads the binary and the `public/` assets folder to the remote host.
6. **Activate**: Triggers the final activation (e.g., `systemctl restart`).

**Atomic Rollbacks**: If the `Activate` step fails, Lurk automatically attempts to restore the previous binary backup and restart the service, minimizing downtime.

### `lurk deploy init`
**Purpose**: Configuration Bootstrapping.
Use this to generate or update your deployment configuration file.

- **What it does**:
  - Scans `.env` or `.example.env` to identify which secrets your app needs.
  - Creates/updates `lurk.yaml` with the required `env_vars` mapping.

### `lurk deploy init --github-actions`
**Purpose**: Full Workflow Bootstrapping.
Use this once at the start of your project or when changing your deployment strategy.

- **What it does**:
  - Generates `lurk.yaml` (same as `lurk deploy init`).
  - Generates a professional GitHub Actions workflow (`.github/workflows/deploy.yml`) tailored to your chosen provider, automatically plumbing necessary authentication secrets (e.g., `DEPLOY_SSH_KEY`, `VPS_IP`, `VPS_USER`).

### `lurk kill [port]`
**Purpose**: Port Recovery.
Useful when a previous process didn't shut down correctly and is blocking your port.
- **Usage**: `lurk kill 3000` or simply `lurk kill`.
- **What it does**: Forcefully terminates any process holding the specified TCP port across all platforms (Linux, macOS, Windows). If no port is specified, it dynamically detects the target port by parsing the `port` value in the `Config` record in `Main.hs`. If the value is a non-numeric env var reference, it resolves it from the corresponding `.env` file. Falls back to `3000`.

### `lurk new <type>`
**Purpose**: Project Scaffolding.
Use this to create a new Lurk project from a scaffold template.

- **Usage**: `lurk new website`
- **What it does**:
  1. Lists available scaffold types from the built-in templates.
  2. Prompts for target location:
     - **Root directory (.)**: All files flat in the current directory.
     - **Web/ subdirectory**: Scaffold files go into `./Web/`, root files in `./`.
     - **Custom directory**: Scaffold files go into `./<dir>/`, root files in `./`. Directory name is automatically capitalized.
  3. Prompts for a project name.
  4. Copies the template files, renames the `.cabal` file, and updates `name:` and `executable` fields.
  5. For subdirectory options, prefixes all local Haskell module declarations and imports (e.g., `Router` becomes `Web.Router`). External imports (`Lurk.*`, `Data.*`, etc.) are left untouched.
  6. Auto-updates the `.cabal` file's `other-modules` on first `lurk run`.

**Available scaffold types**: `website`

---

### `lurk add page`
**Purpose**: Page Scaffolding.
Use this to add a new page to an existing Lurk project.

- **Usage**: `lurk add page` or `lurk add page "About Us"`
- **What it does**:
  1. Generates a **View** module (`View/<Name>.hs`) with a `[lurk|...|]` template.
  2. Generates a **Locale** module (`Locale/<Name>.hs`) with per-language strings.
  3. Injects **paths** into `Paths.hs` (language-aware routes).
  4. Injects a **controller action** into the selected controller.
  5. Injects a **GET route** into `Router.hs`.

- **Target options**: Root (`.`), `Web/` subdirectory, or custom directory. Module names are prefixed automatically (e.g., `Web.View.AboutUs`).
- **Controller injection**: Adds `import View.<Name>` and `import Locale.<Name> qualified as <Name>`, plus the action.

---

### `lurk add form`
**Purpose**: Interactive Form Scaffolding.
The most flexible form generator in any web framework. No other framework generates a complete, type-safe form with anti-abuse guards, flash messages, CSRF protection, and correct routing in a single interactive command.

- **Usage**: `lurk add form`
- **What it does**: Walks you through a series of prompts, then generates/modifies exactly the files you need.

#### Interactive Prompts

| Prompt | Options | What it affects |
|--------|---------|-----------------|
| **Module location** | Root, `Web/`, Custom | Module prefix for all generated code |
| **Target page** | Lists actual View files + "Multiple pages → Partial" | Where the form HTML lives |
| **Submission handling** | Redirect to `/` or Show a message (flash) | Controller generates `redirect` or `flashSuccess` + `redirect` |
| **Controller** | Existing `Form.hs` or custom controller | Which file gets the POST action |
| **Form name** | Free text (e.g., `contact`) | Action name (`contactPostAction`), form function (`contactForm`) |
| **Honeypot field** | Default: `honeypot` | Anti-bot hidden field name |
| **Min submit time** | Default: `3` seconds | Timing guard threshold |

#### What Gets Generated

**Controller** (`Controller/Form.hs` or custom):
- POST action with `validateForm` pipeline
- Guards: honeypot, minSubmitTime, mxRecord
- Flash success/error messages (when selected)
- Redirect to the page where the form lives (not `/`)
- `import Lurk.Form (setFormLoadTime)` injected automatically

**View** (embedded in selected page's View or `Partial.hs`):

- `[lurk|...|]` form function with `{{?csrfToken}}` implicit parameter
- `action="{{?currentPath}}"` — posts to its own page's route
- `{{renderFlashMaybe mFlash}}` for flash display (when selected)
- Reusable as `{{contactForm}}` or `{{contactForm mFlash}}`

**Route** (`Router.hs`):

- POST route injected next to the existing GET route
- Or route comments for Partial (attach to any page)

**GET action** (in controller):
- `setFormLoadTime` injected for timing guard
- `mFlash <- getFlash` injected when flash is enabled
- View call updated with `mFlash` parameter

#### The Four Combinations

| | Redirect | Flash |
|---|----------|-------|
| **Specific page** | Form function in selected View, redirect to page path | + `Maybe Flash` param, `flashHtml` helper with embedded JS |
| **Partial** | Form function in `Partial.hs`, route comments | + `Maybe Flash` param, route comments include flash setup |

#### Why This Is Different

No other web framework offers this level of integrated form scaffolding:

- **Laravel** (`make:form`): Generates a empty form class. No guards, no flash, no routing.
- **Rails** (`form_for`): Generates ERB template. No anti-abuse, no CSRF setup.
- **Django**: `startform` generates a Python class. No HTML, no routing, no guards.
- **Next.js**: No form scaffolding at all. Manual everything.

Lurk generates **all layers at once** (controller, view, route, guards, flash, CSRF) as compile-time safe code that integrates with your existing codebase. The generated code uses the same patterns you'd write by hand: `ViewCtx`, implicit params, `[lurk|...|]` quasiquoter, composable `FormGuard` pipeline.

### `lurk add email`
**Purpose**: Email Template Scaffolding.
Generates a paired HTML + plain text email view, with optional locale support and controller injection.

- **Usage**: `lurk add email` or `lurk add email "Welcome"`
- **What it does**: Walks you through a series of prompts, then generates the email template files.

#### What Gets Generated

**View** (`View/Email/<Name>.hs`):
- Admin: `<Name>Fields` record with `name` and `email` fields, `name :: Fields -> Html` function
- Thank-you: `name :: (?lang :: Language) => Text -> Html` with locale lookup
- Plain text version (`<name>Text`) alongside HTML
- USAGE block with import paths and `sendEmail` example (when not injecting)

**Locale** (`Locale/Email/<Name>.hs`) — Thank-you only:
- `<Name>Locale` record with `subject`, `greeting`, `body`, `signoff`
- `locale :: Language -> <Name>Locale` with English stubs for all project languages

**Controller** (when "use now" = yes):
- `import View.Email.<Name>` injected after last import
- Commented send block with `smtpConfig`, `sendEmail`, `Email{..}` — real imports, TODO args

---

### Provider Deep-Dive

#### 1. SSH Provider (Direct VPS)
The most common choice for simple VPS deployments. It uses SSH for commands and Rsync for fast file transfers.
```yaml
config:
  host: "vps.example.com"        # IP or Domain of your server
  user: "deploy"                 # User with sudo access to systemctl
  path: "/var/www/my-app"        # Absolute path for the app and binary
  service_name: "my-app"         # Name of the systemd service to create/manage
  activate_cmd: "sudo systemctl restart my-app"
```

#### 2. Docker Provider (Containerized)
Best for scaling and environment consistency.
```yaml
config:
  registry: "ghcr.io/user/my-app" # Target image registry
  dockerfile: "Dockerfile"        # Path to your Dockerfile
  tag: "latest"                   # Image tag to use
```

#### 3. Shell Provider (Custom Scripts)
For complex legacy environments where a custom script is required.
```yaml
config:
  script: "./scripts/deploy.sh"   # Path to your custom shell script
  service_name: "my-app"          # Used for binary naming
```

---

## 🛠 Deployment Addendum

### 1. Preliminaries
Before your first deployment, ensure:
- **Toolchain**: GHC and Cabal are installed on your local machine.
- **Server Access**: You have SSH key-based access to the VPS.
- **Permissions**: The deployment user has permissions to create directories in the target `path` and run `sudo systemctl`.

### 2. The Setup Process
The recommended path to production:
1. **Configure**: Run `lurk deploy init` to generate `lurk.yaml`.
2. **CI/CD**: Run `lurk deploy init --github-actions` to also generate your GitHub Action.
3. **Secret Setup**: 
   - Add your SSH/Docker keys and App secrets to GitHub.
4. **Push**: Commit your code and push to `main`. GitHub Actions will handle the rest.

### 3. Strategy Comparison

| Feature | SSH | Docker | Shell |
| :--- | :--- | :--- | :--- |
| **Speed** | Very Fast (Rsync) | Medium (Push/Pull) | Variable |
| **Isolation** | Shared OS | High (Containers) | Low |
| **Setup Effort** | Low | Medium | High |
| **Best For** | Small-Medium VPS | Kubernetes/Cloud | Legacy/Custom |
