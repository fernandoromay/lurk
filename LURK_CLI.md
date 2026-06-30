# Lurk CLI Reference

## Installation

```bash
cabal install exe:lurk
```

Installs to `~/.cabal/bin/lurk` (Linux/macOS) or `%APPDATA%\cabal\bin\lurk.exe` (Windows).
Make sure it's in your `PATH`.

Update to latest:
```bash
cabal install exe:lurk --overwrite-policy=always 2>&1
```

---

## Core Commands

All commands support `--help` / `-h`.

### `lurk run`

Starts the dev server. Loads `.env`, scans source directories for new modules, updates the `.cabal` file, and runs `cabal run -v0`.

### `lurk build`

Same as `run` but only compiles — no server start. Use to verify your project builds.

### `lurk deploy`

Builds a production binary and deploys it. Pipeline: setup remote environment, validate connectivity, build binary, transfer files, activate service. If activation fails, automatically rolls back to the previous binary.

### `lurk deploy init`

Generates `lurk.yaml`. Scans `.env` to identify required secrets and maps them in `env_vars`.

### `lurk deploy init --github-actions`

Generates `lurk.yaml` plus a GitHub Actions workflow (`.github/workflows/deploy.yml`). The workflow uses SSH deployment with secrets: `DEPLOY_SSH_KEY`, `VPS_IP`, `VPS_USER`.

### `lurk kill [port]`

Kills whatever process is holding the given TCP port. If no port is given, reads the `port` field from `Main.hs` config. Falls back to `3000`.

### `lurk new <type>`

Scaffolds a new project. Currently available: `website`.

Prompts for target location (root, `Web/` subdirectory, or custom directory), project name, then copies template files, renames the `.cabal` file, and prefixes local module imports for subdirectory layouts.

### `lurk add page [name]`

Adds a new page. Generates a View module, Locale module, injects paths into `Paths.hs`, a controller action, and a GET route into `Router.hs`.

### `lurk add form`

Interactive form scaffolding. Walks you through prompts (module location, target page, submission handling, controller, form name, honeypot field, min submit time), then generates all layers at once:

- **Controller**: POST action with honeypot, timing, and MX guards. Flash messages if selected.
- **View**: `[lurk|...|]` form with CSRF token, posts to its own route. Flash display if selected.
- **Route**: POST route injected next to the page's GET route.
- **GET action**: Timing guard setup, flash retrieval, view call updated.

### `lurk add email [name]`

Email template scaffolding. Generates paired HTML + plain text email views with optional locale support and controller injection.

---

## Providers

### SSH (Direct VPS)

Uses SSH for commands and rsync for file transfers. Transfers binary, `public/` assets, and `.env` to the remote host.

```yaml
provider: ssh
config:
  host: "vps.example.com"
  user: "deploy"
  path: "/var/www/my-app"
  service_name: "my-app"
  activate_cmd: "sudo systemctl restart my-app"
```

### Docker (Containerized)

Builds and pushes a Docker image to a registry.

```yaml
provider: docker
config:
  registry: "ghcr.io/user/my-app"
  dockerfile: "Dockerfile"
  tag: "latest"
```
