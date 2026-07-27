---
name: setup-local-environment
description: Set up or restore the full local development environment for bi-etl-ejuice. Covers the uv-managed Python environment, dependencies, token variables, DAG file generation, and the local Airflow (Astro) stack. Use when the user is onboarding, setting up a new machine, or the local environment is broken/stale.
---

# Setup Local Environment

The repo is managed with **[uv](https://docs.astral.sh/uv/)**. `make install` runs `uv sync`
across the workspace packages and the standalone `bietlejuice-runtime`; everything else runs
through `uv run`. There is **no** pyenv/virtualenv to create or activate by hand — never run
bare `python3`, `pip install`, `python -m venv`, or pyenv (see `AGENTS.md` → "Environment & toolchain").

## When to use

- First-time setup on a new machine or after a clean clone
- Returning after a long break and needing to resync everything
- Recovering from a broken local Airflow stack
- User says "my local environment is broken" or "set up local"

> The dev container is the recommended path for day-to-day work (it bakes in uv, Java, a
> warmed wheel cache, and a single Python env). See `README.md` → "Recommended: Dev container".
> The steps below cover the host-native setup; inside the container, skip the prerequisite
> install and start at Step 1.

---

## Step 0 — Check prerequisites

Before running any commands, verify the following tools are installed. Run each check and
surface any that are missing:

```bash
# Check uv (drives make install, uv run, wheel builds)
uv --version

# Check Astronomer CLI (astro)
astro version

# Check Docker (required by Astro)
docker info --format '{{.ServerVersion}}'

# Check Docker BuildKit (required for GITHUB_TOKEN secret mounts on image builds)
docker buildx version || docker info | grep -i buildkit
export DOCKER_BUILDKIT=1

# Check Colima resources (if using Colima instead of Docker Desktop)
colima list
```

| Tool | Install command if missing |
|------|---------------------------|
| uv | `brew install uv` — or `curl -LsSf https://astral.sh/uv/install.sh \| sh` (see https://docs.astral.sh/uv/getting-started/) |
| astro CLI | `brew install astronomer/tap/astro` |
| Docker Desktop or Colima | Docker Desktop: https://www.docker.com/products/docker-desktop — or Colima: `brew install colima && colima start --cpu 4 --memory 6` |
| docker buildx | See install steps below |
| JDK 17 | Required for Spark-related tests/tooling (CI uses OpenJDK 17). `brew install openjdk@17` |

uv manages the Python interpreter itself — you do **not** install or pin Python by hand.
Workspace packages target Python 3.10+; `bietlejuice-runtime` uses per-DBR venvs (3.9 / 3.10 / 3.12).
uv downloads a compatible interpreter automatically during `make install`.

**docker buildx install** (required if using Colima or Docker Engine without BuildKit):
```bash
BUILDX_VERSION=$(curl -s https://api.github.com/repos/docker/buildx/releases/latest | jq -r '.tag_name')
mkdir -p ~/.docker/cli-plugins
curl -SL -o ~/.docker/cli-plugins/docker-buildx "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.darwin-arm64"
chmod +x ~/.docker/cli-plugins/docker-buildx
```

**Colima minimum resources**: If using Colima, it must have **at least 4 CPUs and 6 GB RAM**.
The default (2 CPUs / 2 GB) causes the Airflow webserver (gunicorn) to crash as a zombie
process. Check and resize:
```bash
colima list  # check current resources
colima stop && colima start --cpu 4 --memory 6  # resize if needed
```

Do NOT proceed if Docker is not running — the Airflow stack requires it.

---

## Step 1 — Set up environment variables

Run:
```bash
make setup-local-variables
```

This sets `GITHUB_TOKEN`, `DATABRICKS_TOKEN`, and `DATABRICKS_USERNAME` into `~/.zshrc` (or
`~/.bashrc`). It prompts interactively — inform the user they will be asked to enter their tokens.

**After it completes**, tell the user:
> "Restart your terminal (or run `source ~/.zshrc`) before continuing so the variables are available in the current session."

If the variables are already set (e.g. the user has done this before), the script skips them
automatically. No action needed.

Where to get the tokens:
- `GITHUB_TOKEN`: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token (needs `read:packages` scope; also required by `uv sync` to resolve private Git deps such as `quintoandar-logger`)
- `DATABRICKS_TOKEN`: https://docs.databricks.com/dev-tools/api/latest/authentication.html#generate-a-personal-access-token — **select scope "All APIs"** (not "BI Tools", which is too restrictive for DAG execution)
- `DATABRICKS_USERNAME`: the user's `@quintoandar.com.br` email address

---

## Step 2 — Install dependencies

```bash
make install
```

This runs `uv sync` for each workspace package (`bietlejuice-core`,
`bietlejuice-airflow`, `bietlejuice-airflow-operators`, `bietlejuice-airflow-plugins`,
`bietlejuice-compiler`, `emr-cli`) and for the standalone `bietlejuice-runtime` plus its
default `dbr-16-4` test env. (Devcontainer `post-create` runs root `uv sync`, which also
pulls operators/plugins.) uv resolves and caches all dependencies (runtime, test, lint),
including the internal QuintoAndar package index, and provisions a compatible Python
interpreter automatically.

`GITHUB_TOKEN` must be exported in the current session before running (see Step 1) — `uv sync`
needs it to resolve private Git dependencies. If a package fails to install with an auth
error, it almost always means `GITHUB_TOKEN` is missing or invalid. Ask the user to check.

To switch the `bietlejuice-runtime` mirror venv to a different Databricks Runtime (default 16.4):
```bash
make sync-dbr DBR=12.2   # or 13.3 / 16.4
```

After this, run repo code and tests through uv — never bare `python3`:
```bash
uv run --directory packages/bietlejuice-core pytest test/unit/services/test_configuration_service.py -v
uv run --directory packages/bietlejuice-compiler python -c "import yaml; print(yaml.__version__)"
```

---

## Step 3 — Generate DAG Python files

```bash
make create-dag-files
```

This reads all `*_declaration.yml` files and generates the corresponding `*_dag.py` files
under `dags/`, **and** regenerates gitignored parse-time manifests (`.table_manifest`,
`.metadata_manifest`, `.data_quality_manifest`). Must be run before starting Airflow —
otherwise the UI will be empty. Astro "dev" CI uses `make create-astro-dag-files` instead
(domain + migration bundles; no stubs).

If the user only wants DAG files for a specific DAG:
```bash
make create-dag-files dag_name={dag_name}
```

---

## Step 4 — Start the local Airflow environment

```bash
export DOCKER_BUILDKIT=1
make run-local-environment
```

**`DOCKER_BUILDKIT=1` is required** — the image build uses BuildKit secrets for `GITHUB_TOKEN`.

This runs, in order:
1. Load `VAULT_TOKEN` from qli (`astro/scripts/export_qli_vault_token.py`) for VaultBackend
2. `docker build -f astro/Dockerfile` from the **repo root** → tags `bietlejuice-airflow:local` (same Dockerfile as CI/prod; needs `packages/` in context)
3. `astro dev start --image-name bietlejuice-airflow:local` from **`astro/`**
4. Import pools, AWS connection (optional), variables seed, and Databricks connections

Live bind-mounts (via `astro/docker-compose.override.yml`) overlay **core / airflow /
operators / plugins** `src/`, compiler `scripts/`, and `dags/` so code edits are picked up
without rebuild. Rebuild the image when `pyproject.toml` / lock / Dockerfile deps change
(`make restart-local-environment` rebuilds).

Variables resolve via **VaultBackend** (forno Vault path) when `qli login` has a fresh
token; `make run-local-environment` injects `VAULT_TOKEN`. Offline fallback seed:
`make refresh-local-variables` then the import step. Connections stay local (personal
Databricks token) — `connections_path` is omitted from the local Vault kwargs.

This step takes a few minutes on first run (Docker image build). Inform the user.

**Health check timeout is not fatal**: The `astro dev start` command may report
`The webserver health check timed out after 1m0s` — this does NOT mean the startup failed.
The containers continue starting in the background. Verify with `astro dev ps` and check that
all 4 containers (webserver, scheduler, triggerer, postgres) show `running`.

Airflow UI will be available at: http://localhost:8080 (default credentials: `admin` / `admin`).
Note: Astro may assign a different port (e.g. `6563`) on subsequent starts — check the startup
output for the actual URL.

---

## Step 5 — Verify the environment

After startup, verify:

```bash
# Check that Astro containers are running
cd astro && astro dev ps
```

Expected: four containers running (`webserver`, `scheduler`, `triggerer`, `postgres`).

If any container is not running or crashed, check logs:
```bash
cd astro && astro dev logs
```

Common issues:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `unknown flag: --secret` during Docker build | `DOCKER_BUILDKIT` not set or `docker-buildx` not installed | `export DOCKER_BUILDKIT=1` and install buildx (see Step 0) |
| `GITHUB_TOKEN` build error | Token not exported in current shell | `source ~/.zshrc` and run `make run-local-environment` again |
| Gunicorn zombie process (`ps aux` shows `<defunct>`) | Colima has insufficient resources (< 4 CPUs / 6 GB RAM) | `colima stop && colima start --cpu 4 --memory 6` then restart Astro |
| Health check timeout after 1m0s | Normal on first start — containers are still booting | Not an error. Verify with `astro dev ps`; all 4 containers should show `running` |
| Port 8080 already in use | Another service on 8080 | Stop the other service or change port in `astro/docker-compose.override.yml` |
| Empty DAG list in UI | `create-dag-files` not run or failed | Re-run `make create-dag-files` then `make restart-local-environment` |
| Import errors for `databricks_plugin` / `extra_link_plugin` | Image stale or mounts missing | Rebuild with `make restart-local-environment`; confirm `LOCAL_WORKSPACE_FOLDER` |
| `uv sync` auth failure | `GITHUB_TOKEN` missing/invalid for private Git deps | `source ~/.zshrc`, confirm the token has `read:packages`, re-run `make install` |

---

## Quick-restart (returning developer)

If the environment was previously set up, reload the token variables, then resync deps and
restart Astro after pulling new changes:

```bash
source ~/.zshrc        # reload GITHUB_TOKEN / DATABRICKS_* into the session
make install           # re-sync deps if any packages/*/pyproject.toml changed
make create-dag-files
make restart-local-environment
```

`make restart-local-environment` rebuilds `bietlejuice-airflow:local` and restarts the Astro containers.

To fully stop without deleting:
```bash
make stop-local-environment
```

To fully delete all containers and volumes:
```bash
make kill-local-environment
```

---

## Checklist

- [ ] `uv`, `astro`, Docker, `docker buildx`, JDK 17 installed (Step 0)
- [ ] `GITHUB_TOKEN`, `DATABRICKS_TOKEN`, `DATABRICKS_USERNAME` set and exported
- [ ] `make install` completed without errors (`uv sync` across all packages)
- [ ] `make create-dag-files` completed without errors
- [ ] Four Astro containers running (`webserver`, `scheduler`, `triggerer`, `postgres`)
- [ ] Airflow UI accessible at http://localhost:8080
- [ ] DAGs visible in the Airflow UI
