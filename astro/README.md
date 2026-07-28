# Astro (`bietlejuice`)

Production / CI image (repo root as build context):

```bash
docker build -f astro/Dockerfile \
  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
  -t bietlejuice-airflow:prod .
```

## Local Airflow (same image + live package mounts)

Prerequisites:

- [Astro CLI](https://www.astronomer.io/docs/astro/cli/install-cli/) installed (`brew install astro` on macOS)
- Docker running — see [Colima setup](https://docs.google.com/document/d/1S1nonH-HBK9-CUX19YczVR2abYchwtGzBDhzclMk7W8/edit?tab=t.0#heading=h.20gk8wb7m9e1) or QuintoAndar's [local-setup](https://github.com/quintoandar/local-setup)
- `GITHUB_TOKEN` and `DATABRICKS_TOKEN` set in your shell (run `make setup-local-variables` once)

All commands run from the **repository root**:

```bash
export DOCKER_BUILDKIT=1
qli login -r -s vault            # once / when the Vault token expires
make create-dag-files            # when declarations or the DAG builder change
make run-local-environment
# UI: http://localhost:8080 (check Astro startup output for the exact URL/port)

make restart-local-environment   # rebuild image + restart containers
make stop-local-environment      # stop containers, preserve state
make kill-local-environment      # stop containers + delete local metadata DB
```

`make run-local-environment` builds `bietlejuice-airflow:local` from the repo root, injects
`VAULT_TOKEN` from qli's cache (`astro/scripts/export_qli_vault_token.py`), then starts Astro
CLI from `astro/` with `--image-name` (the Dockerfile cannot be built from `astro/` alone
because it `COPY`s `packages/`).

## Variables and connections (local)

- **Primary:** VaultBackend (same forno path as the forno Astronomer deployment:
  `apps/forno/astronomer/airflow/variables` on `vault-sandbox`). Wired only in
  `docker-compose.override.yml` (LOCAL DEV ONLY — not the deployed image).
- **Connections:** intentionally **not** loaded from Vault locally — personal
  `DATABRICKS_TOKEN` via `local_connections.json`.
- **Offline fallback:** pruned `local_variables.json` (16 live keys). Regenerate with:

```bash
make refresh-local-variables
```

`runtime-constraints.txt` is a freeze of `astro-runtime:13.8.0-base` — regenerate when bumping that tag. After `pip freeze`, sanitize local `file://` installs that uv cannot parse as constraints (notably `astronomer-providers` and `astro-sdk-python`) to plain `pkg==version` pins; see the header comment in that file.

We stay on Runtime `-base` (build context is the monorepo root; non-base ONBUILD would `COPY . .`). The Dockerfile still mirrors ONBUILD install helpers: `packages.txt` → `install-system-packages`, `requirements.txt` → `install-python-dependencies`. Extra image deps (e.g. `apache-airflow-providers-hashicorp` for `VaultBackend`, same as Beethoven) go in `requirements.txt`. Monorepo `packages/*` + `quintoandar-logger` are installed separately with `uv`.

`astro/config/airflow_local_settings.py` pre-warms the bietlejuice DAG-builder import graph in the dag-processor / scheduler manager so forked parse children inherit warm `sys.modules` (and the global `ConfigurationService` cache). Override with `BIETLEJUICE_PREWARM=always|never`.

`astro/parse-alias-batching.patch` batches DatasetAlias expansion during DAG serialization (one IN query per file instead of one SELECT per task alias).

Local Airflow (`astro/docker-compose.override.yml`) bind-mounts repo-root `dags/` into `/usr/local/airflow/dags`.

## Deployments (CI) — hybrid

| Branch | Pipeline | Image | DAGs |
|--------|----------|-------|------|
| `development` | [`.woodpecker/development.yml`](../.woodpecker/development.yml) | `astro deploy --image` from this repo | S3 mirror of domain bundles under **`s3://artifacts.s3.data.quintoandar.com.br/astronomer/dags-dev/`** (prod artifacts bucket, isolated prefix) → assemble + `astro deploy --dags` |
| `forno` | [`.woodpecker/release.yml`](../.woodpecker/release.yml) | `astro deploy --image` from this repo | `make create-s3-dag-files` → S3 `astronomer/dags/dags/` + clear `bietlejuice/` → `beethoven-deploy-dags` |
| `master` / `hotfix/*` | same `release.yml` | same | same as forno, plus `INCLUDE_VALIDATION=1` for `_validation_bundle_*.py` |

`bietlejuice` Python packages live in the Runtime image — they are **not** uploaded to S3. Release/Dev CI empty-mirrors `…/bietlejuice/` before DAG deploy so a stale bag-local tree cannot shadow site-packages. QuintoML keeps publishing `quintoml/` + `quintoflow/` to the live forno/prod S3 prefixes unchanged.

Codegen: `make create-s3-dag-files` (hybrid) vs `make create-astro-dag-files` (direct Astro path with migration bundles). Local stub workflow remains `make create-dag-files`.
