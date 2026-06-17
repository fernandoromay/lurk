# Lurk CLI Reference

The Lurk CLI is the official deployment and management tool for the Lurk web framework. It is designed to take a Haskell project from local development to a production environment with minimal friction, automating the build, transfer, and activation processes.

## 🚀 Core Commands

### `lurk run`
**Purpose**: Local Development.
Use this when you are actively coding and want to test changes in real-time.

- **What it does**: 
  1. Loads environment variables from `.env` into the process.
  2. Scans your source directories for new Haskell modules and automatically updates the `.cabal` file to ensure they are compiled.
  3. Executes `cabal run`.

### `lurk build`
**Purpose**: Local Verification.
Use this to ensure your project compiles correctly without actually starting the server.

- **What it does**: Performs the same `.env` loading and `.cabal` module updates as `run`, then executes `cabal build`.

### `lurk deploy`
**Purpose**: Production Release.
The core engine of the framework. It executes a strictly ordered pipeline to ensure atomic deployments.

**The Deployment Pipeline**:
1. **Setup**: Provisions the remote environment. For SSH, this means creating the target directory and writing the systemd service file.
2. **Validate**: Verifies that the destination is reachable and ready.
3. **Package**: Runs `cabal build --minimize` to create a production-ready binary. It then uses `cabal list-bin` to find the exact path of the resulting executable, removing any hardcoded path assumptions.
4. **Transfer**: Securely uploads the binary and the `public/` assets folder to the remote host.
5. **Activate**: Triggers the final activation (e.g., `systemctl restart`).

**Atomic Rollbacks**: If the `Activate` step fails, Lurk automatically attempts to restore the previous binary backup and restart the service, minimizing downtime.

### `lurk deploy --init`
**Purpose**: Workflow Bootstrapping.
Use this once at the start of your project or when changing your deployment strategy.

- **What it does**:
  - Scans `.env` or `.example.env` to identify which secrets your app needs.
  - Creates/updates `lurk.yaml` with the required `env_vars` mapping.
  - Generates a professional GitHub Actions workflow (`.github/workflows/deploy.yml`) tailored to your chosen provider.

### `lurk kill [port]`
**Purpose**: Port Recovery.
Useful when a previous process didn't shut down correctly and is blocking your port.
- **Usage**: `lurk kill 3000` (Defaults to 3000 if omitted).
- **What it does**: Forcefully terminates any process holding the specified TCP port.

---

## ⚙️ Configuration (`lurk.yaml`)

Lurk uses a single YAML file to define the "how" and "where" of your deployment.

### Global Structure
```yaml
project: "my-app-name" # Used as the binary name and systemd service name
build: {}              # Space for future build-time optimizations
deploy:
  provider: "ssh"      # One of: "ssh", "docker", "shell"
  env_vars:            # Maps App Secret Name -> GitHub Secret Name
    DATABASE_URL: DB_URL
    STRIPE_KEY: STRIPE_API_KEY
  config:              # Provider-specific settings
    ...
```

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
1. **Configure**: Define your `lurk.yaml` (or use `lurk deploy --init` to start).
2. **Initialize**: Run `lurk deploy --init` to generate your GitHub Action.
3. **Secret Setup**: 
   - Add your `LURK_YAML` (full file content) as a GitHub Secret.
   - Add your SSH/Docker keys and App secrets to GitHub.
4. **Push**: Commit your code and push to `main`. GitHub Actions will handle the rest.

### 3. Strategy Comparison

| Feature | SSH | Docker | Shell |
| :--- | :--- | :--- | :--- |
| **Speed** | Very Fast (Rsync) | Medium (Push/Pull) | Variable |
| **Isolation** | Shared OS | High (Containers) | Low |
| **Setup Effort** | Low | Medium | High |
| **Best For** | Small-Medium VPS | Kubernetes/Cloud | Legacy/Custom |

### 4. GitHub Actions Logic
Lurk uses a "Secret-First" approach for public repositories. Instead of committing `lurk.yaml`, the workflow performs a **Dynamic Injection**:
1. The Action reads the `LURK_YAML` secret.
2. It writes this content to a physical `lurk.yaml` file in the runner's workspace.
3. The `lurk deploy` command reads that file and executes the pipeline.
This keeps your server IP, usernames, and internal paths completely hidden from the public.
