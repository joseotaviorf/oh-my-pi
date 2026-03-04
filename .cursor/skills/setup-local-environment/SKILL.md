---
name: setup-local-environment
description: Set up or restore the full local development environment for bi-etl-ejuice. Covers Python virtualenv, dependencies, token variables, DAG file generation, and the local Airflow (Astro) stack. Use when the user is onboarding, setting up a new machine, or the local environment is broken/stale.
---

# Setup Local Environment

## When to use

- First-time setup on a new machine or after a clean clone
- Returning after a long break and needing to resync everything
- Recovering from a broken local Airflow stack
- User says "my local environment is broken" or "set up local"

---

## Step 0 — Check prerequisites

Before running any commands, verify the following tools are installed. Run each check and surface any that are missing:

```bash
# Check pyenv
pyenv --version

# Check Astronomer CLI (astro)
astro version

# Check Docker (required by Astro)
docker info --format '{{.ServerVersion}}'

# Check Python 3.8.12 is available in pyenv
pyenv versions | grep 3.8.12
```

| Tool | Install command if missing |
|------|---------------------------|
| pyenv | `brew install pyenv` |
| astro CLI | `brew install astronomer/tap/astro` |
| Docker Desktop | Download from https://www.docker.com/products/docker-desktop |
| Python 3.8.12 | `pyenv install 3.8.12` |

Do NOT proceed if Docker is not running — the Airflow stack requires it.

---

## Step 1 — Set up environment variables

Run:
```bash
make setup-local-variables
```

This sets `GITHUB_TOKEN`, `DATABRICKS_TOKEN`, and `DATABRICKS_USERNAME` into `~/.zshrc` (or `~/.bashrc`). It prompts interactively — inform the user they will be asked to enter their tokens.

**After it completes**, tell the user:
> "Restart your terminal (or run `source ~/.zshrc`) before continuing so the variables are available in the current session."

If the variables are already set (e.g. the user has done this before), the script skips them automatically. No action needed.

Where to get the tokens:
- `GITHUB_TOKEN`: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token (needs `read:packages` scope)
- `DATABRICKS_TOKEN`: https://docs.databricks.com/dev-tools/api/latest/authentication.html#generate-a-personal-access-token
- `DATABRICKS_USERNAME`: the user's `@quintoandar.com.br` email address

---

## Step 2 — Create Python virtualenv

Run in sequence:
```bash
make environment
```

This runs `pyenv install -s 3.8.12` (skips if already installed) and creates the `bi-etl-ejuice` virtualenv with `pyenv local`.

If the virtualenv already exists, pyenv will report an error like `already exists`. That is fine — skip to Step 3.

---

## Step 3 — Install dependencies

Run all three in sequence (not parallel — order matters):

```bash
make requirements
make requirements-test
make requirements-lint
```

This installs runtime, test, and lint packages including the internal QuintoAndar package index (`--extra-index-url`). The `GITHUB_TOKEN` variable must be exported in the current session before running (see Step 1).

If any package fails to install due to auth errors, it almost always means `GITHUB_TOKEN` is missing or invalid. Ask the user to check.

---

## Step 4 — Generate DAG Python files

```bash
make create-dag-files
```

This reads all `*_declaration.yml` files and generates the corresponding `*_dag.py` files under `dags/`. Must be run before starting Airflow — otherwise the UI will be empty.

If the user only wants DAG files for a specific DAG:
```bash
make create-dag-files dag_name={dag_name}
```

---

## Step 5 — Start the local Airflow environment

```bash
make run-local-environment
```

This runs, in order:
1. `make setup-bietlejuice` — copies `dags/`, `bietlejuice/`, `scripts/` into `local/astro/`
2. `make clone-local-airflow-plugins` — clones the `forno` branch of airflow-plugins
3. `make clone-local-beethoven` — clones the `forno` branch of beethoven
4. `astro dev start --no-cache --build-secrets id=GITHUB_TOKEN` — builds the Docker image and starts Airflow
5. `make import-variables-and-connections` — seeds Airflow variables and connections

This step takes 3–8 minutes on first run (Docker image build). Inform the user.

**To use a specific plugin branch** (e.g. for testing a plugin change):
```bash
make run-local-environment branch=your-branch-name
```

Airflow UI will be available at: http://localhost:8080 (default credentials: `admin` / `admin`)

---

## Step 6 — Verify the environment

After startup, verify:

```bash
# Check that Astro containers are running
cd local/astro && astro dev ps
```

Expected: three containers running (`webserver`, `scheduler`, `postgres`).

If any container is not running or crashed, check logs:
```bash
cd local/astro && astro dev logs
```

Common issues:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `GITHUB_TOKEN` build error | Token not exported in current shell | Re-export token and run `make run-local-environment` again |
| Port 8080 already in use | Another service on 8080 | Stop the other service or change port in `local/astro/docker-compose.override.yml` |
| Empty DAG list in UI | `create-dag-files` not run or failed | Re-run `make create-dag-files` then `make setup-bietlejuice` then `make restart-local-environment` |
| Plugins import error | Plugin branch mismatch | Try `make run-local-environment branch=forno` |

---

## Quick-restart (returning developer)

If the environment was previously set up and you just need to resync after pulling new changes:

```bash
make create-dag-files
make restart-local-environment
```

This recopies DAGs/code and restarts the Astro containers without a full image rebuild.

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

- [ ] `GITHUB_TOKEN`, `DATABRICKS_TOKEN`, `DATABRICKS_USERNAME` set and exported
- [ ] Python 3.8.12 virtualenv `bi-etl-ejuice` active (`python --version` returns `3.8.12`)
- [ ] `make requirements` completed without errors
- [ ] `make create-dag-files` completed without errors
- [ ] Three Astro containers running (`webserver`, `scheduler`, `postgres`)
- [ ] Airflow UI accessible at http://localhost:8080
- [ ] DAGs visible in the Airflow UI
