---
name: run-dag-locally
description: Run and monitor a specific DAG on the local Airflow environment via Astro CLI. Handles unit tests, selective DAG sync, uploading artifacts to forno S3/Databricks, triggering, and monitoring via the Airflow REST API. Use when the user asks to run a DAG locally, test a DAG, trigger a DAG, kick a DAG, validate a DAG with real data, upload to forno, test changes on Databricks, or deploy artifacts to the staging environment.
---

# Run DAG Locally

## When to use

- After modifying a DAG's Spark job, declaration YAML, or bietlejuice code and wanting to test with real data
- User says "run my DAG locally", "test this DAG", "trigger the DAG", or "kick the DAG"
- Validating that a DAG parses correctly and its tasks execute on Databricks (Forno)

**Important**: The local Airflow orchestrates the DAG, but Spark jobs execute on Databricks via the configured `databricks_conn_id`. This is not a purely offline test — it runs against the Forno staging environment.

---

## Session activation (run at the start of every new terminal)

All `make` commands in this skill (including `make create-dag-files`, `make upload-local-queries`, etc.) must run **locally in the `bi-etl-ejuice` pyenv virtualenv** — NOT inside Docker containers. The virtualenv has Apache Airflow and all dependencies installed.

Activate the session before running any command:

```bash
source ~/.zshrc
eval "$(pyenv init --path)" && eval "$(pyenv init -)" && eval "$(pyenv virtualenv-init -)"
pyenv activate bi-etl-ejuice
```

Verify it worked:
```bash
python --version   # should print Python 3.8.12
python -c "import airflow; print(airflow.__version__)"  # should print 2.10.4
```

If the virtualenv does not exist or Airflow is not installed, run the `setup-local-environment` skill first.

---

## Step 0 — Run unit tests (fastest feedback)

Before starting Airflow, run the relevant unit tests. Identify test files by mirroring the source path:

- `bietlejuice/foo/bar.py` → `tests/unit/foo/test_bar.py`
- `dags/core/{dag}/spark_jobs/*.py` → `tests/core_model_dags/unit/core/{dag}/spark_jobs/test_*.py`

```bash
python -m pytest tests/path/to/test_file.py -v
```

If tests fail, fix them before proceeding — there is no point spinning up Airflow with broken logic.

---

## Step 1 — Check prerequisites

Verify Docker, Astro containers, and environment variables. Run all checks in parallel:

```bash
docker info --format '{{.ServerVersion}}'
```

```bash
cd local/astro && astro dev ps
```

```bash
echo "GITHUB_TOKEN set: $([ -n "$GITHUB_TOKEN" ] && echo yes || echo no)"
echo "DATABRICKS_TOKEN set: $([ -n "$DATABRICKS_TOKEN" ] && echo yes || echo no)"
echo "DATABRICKS_USERNAME set: $([ -n "$DATABRICKS_USERNAME" ] && echo yes || echo no)"
```

If Docker is not running or env vars are missing, follow the `setup-local-environment` skill first.

If Astro containers are **not running at all** (first time or after `kill`), use:
```bash
make run-local-environment
```
This takes 3–8 minutes (full Docker image build). Then skip to Step 3 (verification).

If containers **are already running**, proceed to Step 2.

---

## Step 2 — Regenerate DAG file

After any declaration YAML change, regenerate the DAG Python file. This runs **locally in the virtualenv** (requires Airflow installed — see Session activation above). Do NOT run this inside Docker containers.

```bash
make create-dag-files dag_name={dag_name}
```

---

## Step 3 — Upload artifacts to Forno S3 (mirrors `release.yml` Forno steps)

This step is the local equivalent of the CI/CD `release.yml` pipeline that runs on the `forno` branch. It uploads all artifacts that Databricks and Airflow need to execute jobs in the Forno staging environment.

### Artifact map

| Artifact | Local source | S3 bucket | S3 path |
|---|---|---|---|
| `bietlejuice` wheel | `dist/*.whl` | `artifacts.s3.forno` | `bi-etl-ejuice-local/{username}/` (personal, avoids overwriting shared) |
| Spark job scripts | `dags/**/spark_jobs/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice-local/{username}/spark_jobs/` |
| SQL queries | `dags/**/queries/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/queries/` |
| Data quality files | `dags/**/data_quality/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/data_quality/` |
| JSON schemas | `dags/**/schemas/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/schemas/` |
| Qube Python modules | `bietlejuice/qube/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/bietlejuice/qube/` |
| Init scripts | `scripts/init_script.sh`, `scripts/wonka/*.sh` | `artifacts.s3.forno` | `bi-etl-ejuice/` |

### Decision matrix — upload only what changed

| Changed path | Upload needed | Make target |
|---|---|---|
| `bietlejuice/qube/jobs/**/*.py` | Qube modules only | `make upload-local-qube-jobs` |
| `bietlejuice/**/*.py` (non-qube) | Wheel + spark jobs | `make upload-local-package` |
| `dags/**/spark_jobs/**/*.py` | Spark jobs only | `make upload-local-spark-jobs` |
| `dags/**/queries/**/*.sql` | Queries | `make upload-local-queries` |
| `dags/**/data_quality/**/*.yml` | Data quality | `make upload-local-data-quality` |
| `dags/**/schemas/**/*.json` | Schemas | `make upload-local-schemas` |
| `scripts/init_script.sh` or `scripts/wonka/*.sh` | Init scripts | `make upload-local-init-scripts` |
| Multiple / unsure | Everything | `make upload-forno-release` |

### Full Forno release (equivalent to pushing the `forno` branch)

Run this when you want a complete, clean sync of all artifacts — exactly what CI/CD does:

```bash
make upload-forno-release
```

This runs in sequence: wheel build → spark_jobs → queries → data_quality → schemas → qube modules → init scripts.

### Individual targets (faster for targeted changes)

```bash
# Wheel + spark_jobs (bietlejuice library or core Spark job changes)
make upload-local-package

# SQL queries only
make upload-local-queries

# Data quality YAML only
make upload-local-data-quality

# JSON schemas only
make upload-local-schemas

# Qube Python modules only (no cluster restart needed)
make upload-local-qube-jobs

# Init scripts (init_script.sh + wonka/*.sh) — rarely needed
make upload-local-init-scripts
```

**One-time setup required for the wheel upload**: `local/upload_local_whl_to_s3.py` has a hardcoded placeholder for the local wheel path. Before the first run, open that file and replace `<BIETLEJUICE_FOLDER>` with the absolute path to your local repo:

```python
# local/upload_local_whl_to_s3.py
local_path = '/home/<BIETLEJUICE_FOLDER>/dist/bi_etl_ejuice-0.1.0-py3-none-any.whl'
# → replace with, e.g.:
local_path = '/Users/your-username/Documents/projects/bi-etl-ejuice/dist/bi_etl_ejuice-0.1.0-py3-none-any.whl'
```

**AWS credentials required**: All upload targets call `boto3` or `aws` CLI and need a valid AWS session. QuintoAndar uses **Weep** (Netflix ConsoleMe) for AWS credential brokering, not AWS SSO.

### Weep setup (one-time)

Install Weep v0.3.31 from https://github.com/Netflix/weep/releases/tag/v0.3.31 and create `~/.weep/weep.yaml`:

```yaml
authentication_method: challenge
challenge_settings:
  user: your.email@quintoandar.com.br
consoleme_url: https://consoleme.sre.quintoandar.com.br
mtls_settings:
  old_cert_message: mTLS certificate is too old, please refresh mtls certificate
server:
  http_timeout: 20
  port: 9091
```

### Get AWS credentials before each upload

```bash
# List available roles
/usr/local/bin/weep list

# Export credentials for Forno Stag Data (account 713278628093)
eval $(/usr/local/bin/weep export arn:aws:iam::713278628093:role/sso_DataAndAnalytics_Squad)

# Verify
aws sts get-caller-identity
```

Weep credentials are temporary (~1 hour). Re-run the `eval` command if they expire mid-session.

---

## Step 4 — Selective sync and Airflow image rebuild

**Do NOT use `make restart-local-environment`** — it copies all ~771 DAGs and makes the scheduler slow.

This step is the local equivalent of the CI/CD `astronomer-deploy-dags` step: it rebuilds the Airflow Docker image (from `local/astro/Dockerfile`) and syncs DAG code into the running containers.

Instead, do a targeted copy that includes only the DAG under test:

```bash
# Determine the domain and dag_name from the DAG folder path:
#   dags/{domain}/{dag_name}/  →  e.g. domain=core, dag_name=core_contract

# Clean previous sync
rm -fR ./local/astro/dags || true
rm -fR ./local/astro/bietlejuice || true
rm -fR ./local/astro/scripts || true

# Copy framework essentials (required for DAG parsing)
mkdir -p ./local/astro/dags
cp ./dags/__init__.py ./local/astro/dags/
cp ./dags/dependencies.yaml ./local/astro/dags/
cp -Rf ./dags/dependency_exceptions/ ./local/astro/dags/dependency_exceptions/

# Copy ONLY the target DAG
mkdir -p ./local/astro/dags/{domain}/{dag_name}
cp -Rf ./dags/{domain}/{dag_name}/ ./local/astro/dags/{domain}/{dag_name}/

# Copy shared code (always needed for imports)
cp -Rf ./bietlejuice/ ./local/astro/bietlejuice
cp -Rf ./scripts/ ./local/astro/scripts
```

Then restart the Astro containers (**`DOCKER_BUILDKIT=1` is required**):

```bash
cd ./local/astro && export DOCKER_BUILDKIT=1 && astro dev restart --no-cache --build-secrets id=GITHUB_TOKEN
```

If the restart fails with a permission error on `local/astro/include`:
```bash
sudo chmod 755 ./local/astro/include
```
Then retry the restart.

A TTY error during variable import (`error adding variable DOC_MD_BASE_URL`) is **non-critical** — the containers still run.

### Lightweight alternative: `docker cp` (no rebuild)

When you only changed SQL queries or metadata (no Python code changes in `bietlejuice/`), you can skip the full Docker rebuild and copy files directly into the running containers:

```bash
# Copy the target DAG into both scheduler and webserver containers
SCHED=$(docker ps --filter "name=scheduler" --format "{{.ID}}")
WEB=$(docker ps --filter "name=webserver" --format "{{.ID}}")

docker cp ./dags/{domain}/{dag_name}/ $SCHED:/usr/local/airflow/dags/{domain}/{dag_name}/
docker cp ./dags/{domain}/{dag_name}/ $WEB:/usr/local/airflow/dags/{domain}/{dag_name}/
```

The scheduler will re-parse the DAG within 15–30 seconds. No restart needed. Use the full rebuild path (above) when `bietlejuice/` Python code or plugins changed.

---

## Step 5 — Verify DAG via API

**Use the REST API, not `astro dev run dags list`** — the CLI is very slow.

Wait for the scheduler to parse the DAG (with selective copy, this is near-instant):

```bash
curl -s -u admin:admin http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}
```

Check the response for:
- `has_import_errors: false` — DAG parses correctly
- `last_parsed_time` — updated after the restart

If `has_import_errors` is true, check:
```bash
curl -s -u admin:admin http://localhost:8080/api/v1/importErrors
```

List tasks to confirm all expected tasks are present:
```bash
curl -s -u admin:admin "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/tasks" \
  | python3 -c "import json,sys; data=json.load(sys.stdin); [print(t['task_id']) for t in data['tasks']]; print(f'Total: {data[\"total_entries\"]}')"
```

If `last_parsed_time` has not updated yet, wait 15–30 seconds and retry.

---

## Step 6 — Trigger the DAG

Trigger a manual run with `test_run` mode to avoid impacting downstream dependents:

```bash
curl -s -u admin:admin -X POST \
  "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/dagRuns" \
  -H "Content-Type: application/json" \
  -d '{
    "conf": {
      "run_type": "test_run",
      "load_start_date": "{YYYY-MM-DD}",
      "load_end_date": "{YYYY-MM-DD}"
    }
  }'
```

Save the `dag_run_id` from the response for monitoring.

Choose appropriate date ranges:
- For incremental DAGs: a recent 1–7 day window
- For full-load DAGs: dates are ignored, but still required by the API

---

## Step 7 — Monitor execution

Poll the DAG run and task instance states. Use exponential backoff:
- First check after 15s (cluster provisioning starts)
- Then every 60s (cluster takes 3–5 min to provision)
- Then every 60–120s (Spark job execution)

**Check DAG run state:**
```bash
curl -s -u admin:admin \
  "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/dagRuns/{dag_run_id}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'DAG state: {d[\"state\"]}')"
```

**Check all task instance states:**
```bash
curl -s -u admin:admin \
  "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/dagRuns/{dag_run_id}/taskInstances" \
  | python3 -c "import json,sys; data=json.load(sys.stdin); [print(f'  {t[\"task_id\"]:45s} state={str(t[\"state\"]):15s} duration={t.get(\"duration\",\"\")}') for t in data['task_instances']]"
```

Typical task execution timeline:
- `execute-job-cluster`: 3–5 min (Databricks cluster provisioning)
- `load-*` tasks: 2–5 min each (Spark job execution)
- `data-quality-*` tasks: 10–30s
- `optimize-*` tasks: 1–5 min (may fail on Forno — see common issues)

Stop polling when `state` is `success` or `failed`.

---

## Step 8 — Inspect failures

If any task fails, check its logs:

```bash
curl -s -u admin:admin \
  "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/dagRuns/{dag_run_id}/taskInstances/{task_id}/logs/{try_number}" \
  | tail -40
```

Use `try_number=1` for the first attempt, `2` for the first retry, etc.

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Docker mount permission error on `local/astro/include` | macOS permission issue | `sudo chmod 755 ./local/astro/include` |
| TTY error adding variables on restart | Non-interactive terminal | Non-critical; containers still work |
| `has_import_errors: true` | Python import or YAML syntax error | Check `importErrors` API endpoint for the traceback |
| `last_parsed_time` not updating | Scheduler has not processed the DAG yet | Wait 15–30s and retry (near-instant with selective copy) |
| `optimize-*` task fails | Databricks cluster terminated before optimize finished | Non-critical on Forno; does not affect data correctness |
| Port 8080 already in use | Another service on port 8080 | Stop the other service or edit `local/astro/docker-compose.override.yml` |
| DAG shows 0 tasks | Stale parse from before restart | Wait for `last_parsed_time` to update past the restart time |
| `execute-job-cluster` fails | Databricks connection issue or cluster config | Check Databricks workspace; verify `databricks_conn_id` in declaration |
| `setup.py` wheel build fails with `Parse error at "'-e git+h'"` | `setup.py` reads `requirements-freeze.txt` which contains `-e git+...` editable installs | Change `setup.py` to read from `requirements.txt` instead — it is the curated Databricks dependency list |
| `ModuleNotFoundError` on Databricks (`pymongo`, `trino`, `hierarchical_conf`, etc.) | Wheel was built with empty or incomplete `install_requires` | Build the wheel using `requirements.txt` as the dependency source, not `requirements-freeze.txt` |
| `FileNotFoundException: spark_jobs/{dag_name}/*.py` on Databricks | `make upload-local-package` uploads spark jobs to a **personal** S3 path (`bi-etl-ejuice-local/{username}/spark_jobs/`), but core model DAGs resolve to the **shared** forno path (`github-repos/bi-etl-ejuice/spark_jobs/{dag_name}/`) | Manually upload with `aws s3 cp` to the shared path (see Step 3a below) |
| `DELTA_CREATE_TABLE_SCHEME_MISMATCH` | POC or schema change conflicts with existing Delta table on forno | Delete the old table: `aws s3 rm s3://5a-datalake-forno/{layer}/{schema}/{table}/ --recursive`, then re-trigger |
| `DELTA_PATH_DOES_NOT_EXIST` after deleting a table | Metastore still references the old table but the S3 path was removed | The first run after deletion must create the table fresh; if the pipeline uses MERGE, it may fail. Drop the metastore entry via Databricks notebook: `spark.sql("DROP TABLE IF EXISTS {schema}.{table}")` before re-triggering |
| Task succeeds but target table is empty | Date range in `load_start_date`/`load_end_date` does not match data available in forno | Check what dates exist in the source table first (query via Databricks or sample data CSV), then trigger with matching dates |
| AWS credentials expire mid-session | Weep credentials last ~1 hour; long cluster provisioning can exceed TTL | Re-run `eval $(/usr/local/bin/weep export arn:aws:iam::713278628093:role/sso_DataAndAnalytics_Squad)` before each upload step |
| `unknown flag: --secret` during `astro dev restart` | `DOCKER_BUILDKIT` not set or `docker-buildx` not installed | `export DOCKER_BUILDKIT=1`; install buildx if missing (see setup-local-environment skill) |

---

## Step 3a — Core model DAGs: upload spark jobs to shared forno path

The `make upload-local-spark-jobs` target uploads to a **personal** S3 path under `bi-etl-ejuice-local/{username}/`. However, core model DAGs (and some other DAG types) resolve spark job paths from the **shared** forno location. When `FileNotFoundException` occurs on Databricks, upload directly to the shared path:

```bash
# Upload spark jobs to the SHARED forno path (for core model DAGs)
aws s3 cp dags/{domain}/{dag_name}/spark_jobs/{job_file}.py \
  s3://databricks.s3.forno.data.quintoandar.com.br/github-repos/bi-etl-ejuice/spark_jobs/{dag_name}/{job_file}.py \
  --acl bucket-owner-full-control

# Upload config YAMLs too
aws s3 cp dags/{domain}/{dag_name}/spark_jobs/forno_conf.yml \
  s3://databricks.s3.forno.data.quintoandar.com.br/github-repos/bi-etl-ejuice/spark_jobs/{dag_name}/forno_conf.yml \
  --acl bucket-owner-full-control
```

---

## Step 3b — Wheel build: use `requirements.txt`, not `requirements-freeze.txt`

The `setup.py` historically reads `requirements-freeze.txt` (a local `pip freeze` dump), which contains editable installs (`-e git+...`), platform-specific pins, and transitive dependencies that conflict on Databricks.

If `make upload-local-package` fails during the wheel build, or the wheel causes `ModuleNotFoundError` on Databricks, update `setup.py` to read from `requirements.txt`:

```python
# setup.py — use the curated Databricks dependency list
with open('requirements.txt') as f:
    install_requirements = [
        line.strip()
        for line in f.read().splitlines()
        if line.strip() and not line.strip().startswith('#')
    ]
```

The `requirements.txt` file header says "The requirements are for Spark jobs in Databricks" — it is the correct source of truth.

---

## Step 6a — Choose date ranges that match forno data

Forno is a staging environment and may not have recent CDC data. Before triggering, verify what dates are available in the source table:

- Check sample data CSVs if available (e.g. `dags/{domain}/{dag_name}/sample_data/`)
- Or query the source table directly on the Databricks forno workspace
- The Airflow trigger API requires `load_start_date` and `load_end_date` even when the source table has no data for that range — the job will succeed silently with 0 rows written

For initial POC testing, use a wide date range to capture all available data:
```json
{
  "conf": {
    "run_type": "test_run",
    "load_start_date": "2019-01-01",
    "load_end_date": "2026-12-31"
  }
}
```

---

## Step 8a — Inspect Databricks run output for detailed errors

When Airflow logs only show `RunState failed with terminal state: FAILED. Message: Workload failed`, extract the Databricks run ID from the Airflow log and query the Databricks API for the full stack trace:

```bash
# Find the task run ID in Airflow logs (look for "Run details:" or "task run ID:")
RUN_ID=<run_id_from_logs>

# Get full error + stack trace from Databricks
curl -s -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "https://dbc-324f044d-4b9d.cloud.databricks.com/api/2.1/jobs/runs/get-output?run_id=$RUN_ID" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error','')); print('---'); print(d.get('error_trace','')[:3000])"
```

---

## Checklist

- [ ] Unit tests pass for the changed modules
- [ ] Docker running and Astro containers up
- [ ] AWS session valid (`aws sts get-caller-identity`) — re-check before each upload step
- [ ] `setup.py` reads `requirements.txt` (not `requirements-freeze.txt`) for `install_requires`
- [ ] `local/upload_local_whl_to_s3.py` has the correct absolute path (not `<BIETLEJUICE_FOLDER>`)
- [ ] DAG file regenerated (`make create-dag-files dag_name=...`)
- [ ] Forno S3 artifacts uploaded — use the decision matrix in Step 3 to pick the right target(s), or run `make upload-forno-release` for a full sync
- [ ] For core model DAGs: spark jobs also uploaded to the **shared** forno path (Step 3a)
- [ ] Selective sync completed (only target DAG in `local/astro/dags/`)
- [ ] Astro containers restarted (Airflow image rebuilt)
- [ ] DAG has no import errors (`has_import_errors: false`)
- [ ] All expected tasks visible via API
- [ ] Trigger date range matches available data in forno source tables (Step 6a)
- [ ] DAG triggered with `test_run` mode
- [ ] All critical tasks (load, data-quality) completed successfully
- [ ] If task fails: checked Databricks run output for full stack trace (Step 8a)
