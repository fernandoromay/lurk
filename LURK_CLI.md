# Lurk CLI Reference

The Lurk CLI is the official deployment and management tool for the Lurk web framework. It is designed to take a Haskell project from local development to a production environment with minimal friction, automating the build, transfer, and activation processes.

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

### `lurk deploy --yaml`
**Purpose**: Configuration Bootstrapping.
Use this to generate or update your deployment configuration file.

- **What it does**:
  - Scans `.env` or `.example.env` to identify which secrets your app needs.
  - Creates/updates `lurk.yaml` with the required `env_vars` mapping.

### `lurk deploy --githubaction`
**Purpose**: Workflow Bootstrapping.
Use this to generate the CI/CD pipeline configuration.

- **What it does**:
  - Generates a professional GitHub Actions workflow (`.github/workflows/deploy.yml`) tailored to your chosen provider, automatically plumbing necessary authentication secrets (e.g., `DEPLOY_SSH_KEY`, `VPS_IP`, `VPS_USER`).

### `lurk deploy --init`
**Purpose**: Full Workflow Bootstrapping.
Use this once at the start of your project or when changing your deployment strategy.

- **What it does**:
  - Runs `lurk deploy --yaml` followed by `lurk deploy --githubaction` to fully bootstrap your deployment configuration and workflow in one command.

### `lurk kill [port]`
**Purpose**: Port Recovery.
Useful when a previous process didn't shut down correctly and is blocking your port.
- **Usage**: `lurk kill 3000` or simply `lurk kill`.
- **What it does**: Forcefully terminates any process holding the specified TCP port across all platforms (Linux, macOS, Windows). If no port is specified, it dynamically detects the target port by checking the `PORT` environment variable, falling back to parsing `Config.hs` for `defaultPort`, and finally defaulting to `3000`.

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
1. **Configure**: Define your `lurk.yaml` (or use `lurk deploy --yaml` to start).
2. **Initialize**: Run `lurk deploy --githubaction` to generate your GitHub Action.
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
