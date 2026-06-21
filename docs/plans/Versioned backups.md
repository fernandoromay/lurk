# Plan: Versioned Release-Based Deployment

## Current State

SSH deploy does `mv app app.bak` -- one backup level, destroyed each deploy.
Docker does `:latest` -> `:previous` -- same problem.

## Target Structure

```
/var/www/my-app/                       # path from lurk.yaml
├── my-app                             # symlink -> releases/2026.06.21-091530/my-app
├── releases/
│   ├── 2026.06.20-153045/
│   │   └── my-app                     # binary
│   └── 2026.06.21-091530/
│       └── my-app                     # binary
├── releases.json                      # release metadata (single source of truth)
├── public/
├── .env
└── logs/
```

- Release dirs use **timestamps** (`YYYY.MM.DD-HHMMSS`). No `.cabal` version or git required.
- `releases.json` stores metadata per release. Optional fields are null when unavailable.
- `max_releases` config prunes oldest: removes both the directory and the JSON entry.
- Symlink always points to the current release.

---

## `releases.json` Schema

```json
{
  "current": "2026.06.21-091530",
  "releases": {
    "2026.06.21-091530": {
      "version": "0.4.2",
      "git-commit": "a3f8b2c",
      "deployed-at": "2026-06-21T09:15:30-03:00"
    },
    "2026.06.20-163210": {
      "version": "0.4.2",
      "git-commit": "8f2d1e3",
      "deployed-at": "2026-06-20T16:32:10-03:00"
    }
  }
}
```

| Field | Source | Required |
|-------|--------|----------|
| `current` | Updated on every deploy | Yes |
| Key (dir name) | Timestamp at deploy time | Yes |
| `version` | `.cabal` `version:` field, null if missing | No |
| `git-commit` | `git rev-parse --short HEAD`, null if no `.git` | No |
| `deployed-at` | ISO 8601 timestamp | Yes |

**Keyed by dir name** instead of array:
- O(1) lookup
- No duplicate entries possible
- Key IS the directory name, no ambiguity

---

## Changes

### 1. `Deploy.hs` -- Add metadata detection + config

```haskell
-- | Collect release metadata at deploy time
data ReleaseMetadata = ReleaseMetadata
    { rmVersion   :: Maybe String    -- from .cabal, null if absent
    , rmGitCommit :: Maybe String    -- from git, null if no .git
    , rmDeployedAt :: String         -- ISO 8601 timestamp
    }

-- | Generate timestamp dir name: "2026.06.21-091530"
getReleaseDir :: IO String

-- | Collect metadata from environment (.cabal, git)
getReleaseMetadata :: IO ReleaseMetadata

-- | Add max_releases to DeploySettings
data DeploySettings = DeploySettings
    { provider    :: String
    , config      :: Value
    , env_vars    :: Maybe (Map String String)
    , max_releases :: Maybe Int       -- default: 5
    }
```

**`getReleaseDir`**: `getCurrentTime` -> format as `YYYY.MM.DD-HHMMSS`.

**`getReleaseMetadata`**:
- `version`: parse `version:` from first `.cabal` file (same as `getProjectName` pattern). Null if no `.cabal` or no `version:` line.
- `git-commit`: run `git rev-parse --short HEAD` in a try/catch. Null on failure.
- `deployed-at`: `getCurrentTime` formatted as ISO 8601.

### 2. `Deploy/SSH.hs` -- Rewrite for releases structure

**`setup`:**
- `mkdir -p {{path}}/releases` (instead of just `{{path}}`)
- Create empty `releases.json` if it doesn't exist: `echo '{"current":null,"releases":{}}' | tee {{path}}/releases.json`
- systemd `ExecStart` = `{{path}}/{{service_name}}` (the symlink)

**`transfer`:**
- Get timestamp dir via `getReleaseDir`
- Collect metadata via `getReleaseMetadata`
- Create `{{path}}/releases/{{timestamp}}/` on remote
- rsync binary to `{{path}}/releases/{{timestamp}}/{{service_name}}`
- Delete old symlink, create new: `ln -sfn releases/{{timestamp}}/{{service_name}} {{path}}/{{service_name}}`
- rsync `public/` to `{{path}}/public/` (always rsync, simple and idempotent)
- Transfer `.env` if present (always overwrite — developer chose to include it)
- Update `releases.json` on remote:
  - Set `current` to new timestamp
  - Add new entry with metadata
  - If `releases` count > `max_releases`, prune oldest (delete dir + remove entry)
- Prune old release directories beyond `max_releases`

**`rollback`:**
- Read `releases.json` from remote
- Pick second entry (newest after current) or specific version if provided
- Swap symlink to target release
- Update `current` in `releases.json`
- Restart service

### 3. `Deploy/Docker.hs` -- No changes for now

Version tags alongside `:previous` can be added later. Docker uses image tags, not directories. `releases.json` is SSH-specific.

### 4. `Deploy/Shell.hs` -- No changes

Delegates to external script. No backup logic in lurk.

### 5. `cli/Main.hs` -- Add `versions` and `rollback` commands

```bash
lurk versions          # list releases from releases.json
lurk rollback          # rollback to previous release
lurk rollback <timestamp>  # rollback to specific release
```

**`lurk versions` output:**
```
  2026.06.21-091530  v0.4.2  a3f8b2c  dev  (current)
  2026.06.20-163210  v0.4.2  8f2d1e3  dev
  2026.06.20-153045  v0.4.1  3b7c9a0  main
```

**`lurk rollback` output:**
```
Rolling back from 2026.06.21-091530 to 2026.06.20-163210...
Symlink updated. Restarting service...
Done.
```

### 6. `DeployProvider` class -- No changes

Keep class as-is. `listReleases`/`rollbackTo` are SSH-specific regular functions, not class methods.

---

## Pruning Strategy

`max_releases` (default: 5) limits both:
1. **Directories** under `releases/` -- oldest deleted first
2. **Entries** in `releases.json` -- oldest removed from JSON

Prune timing: during `transfer`, after successful deploy and symlink swap.

Pruning order:
1. Read `releases.json`
2. Sort keys (timestamps sort lexicographically = chronologically)
3. If count > `max_releases`, delete oldest directories from remote
4. Remove corresponding entries from `releases.json`
5. Write updated `releases.json` to remote

---

## Files Modified

| File | Change |
|------|--------|
| `Lurk/Deploy.hs` | Add `ReleaseMetadata`, `getReleaseDir`, `getReleaseMetadata`, `max_releases` field |
| `Lurk/Deploy/SSH.hs` | Rewrite `setup`/`transfer`/`rollback` for releases + `releases.json`, add `listReleases`/`rollbackTo` |
| `cli/Main.hs` | Add `versions`/`rollback` commands |

## No Changes

| File | Reason |
|------|--------|
| `Deploy/Docker.hs` | Image tags, not directories. Can add later. |
| `Deploy/Shell.hs` | Delegates to external script |
| `DeployProvider` class | No new class methods needed |
| `lurk.cabal` | No new dependencies (aeson already used) |

---

## Open Questions

1. **Public assets**: Always rsync to `{{path}}/public/` (shared, not per-release). Optimized later if needed.

2. **`.env`**: Transferred to `{{path}}/.env` (shared, not per-release). Same as today.

3. **Rollback without args**: Silently rollback to previous (second-to-last in JSON). No prompt -- CLI tool, not interactive.

4. **Collision**: Two deploys in the same second would produce the same timestamp. Mitigation: append `-2`, `-3` etc. by checking if dir already exists on remote.

5. **`releases.json` race condition**: Two simultaneous deploys could corrupt the JSON. Low risk (single developer deploying). If needed later, use `ssh mkdir` as an atomic lock.

6. **Symlink target**: `{{path}}/{{service_name}}` -> `releases/{{timestamp}}/{{service_name}}`. Binary is inside the release dir. The symlink resolves to the binary path.
