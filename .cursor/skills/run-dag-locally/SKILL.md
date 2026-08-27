---
name: run-dag-locally
description: Run and monitor a specific DAG on the local Airflow environment via Astro CLI. Handles unit tests, uploading artifacts to forno S3/Databricks, triggering, and monitoring via the Airflow REST API. Use when the user asks to run a DAG locally, test a DAG, trigger a DAG, kick a DAG, validate a DAG with real data, upload to forno, test changes on Databricks, or deploy artifacts to the staging environment.
---

# Run DAG Locally

## When to use

- After modifying a DAG's Spark job, declaration YAML, or bietlejuice code and wanting to test with real data
- User says "run my DAG locally", "test this DAG", "trigger the DAG", or "kick the DAG"
- Validating that a DAG parses correctly and its tasks execute on Databricks (Forno)

**Important**: Spark execution depends on the DAG cluster config. **EMR pilot DAGs** (e.g. Qube) run Spark on **AWS EMR**; most other DAGs still use **Databricks** via `databricks_conn_id`. Local Airflow only orchestrates — jobs run in Forno.

---

## Environment

All `make` commands run from the repository root. `uv` manages the Python environment and dependencies.

Verify the environment:
```bash
uv run python --version                                        # 3.12.x
uv run python -c "import airflow; print(airflow.__version__)"  # 2.11.2
```

If `uv` is not installed or packages are missing, run `make install` first. Alternatively, work inside the dev container where everything is pre-configured.

---

## Step 0 — Run unit tests (fastest feedback)

Before starting Airflow, run the relevant unit tests. Identify test files by mirroring the source path:

- `packages/bietlejuice-runtime/src/bietlejuice/foo/bar.py` → `packages/bietlejuice-runtime/test/unit/foo/test_bar.py`
- `dags/core/{dag}/spark_jobs/*.py` → `packages/bietlejuice-runtime/test/core_model_dags/unit/core/{dag}/spark_jobs/test_*.py`

```bash
uv run --directory packages/bietlejuice-runtime pytest test/unit/path/to/test_file.py -v
```

If tests fail, fix them before proceeding — there is no point spinning up Airflow with broken logic.

---

## Step 1 — Check prerequisites

Verify Docker, Astro containers, and environment variables. Run all checks in parallel:

```bash
docker info --format '{{.ServerVersion}}'
```

```bash
cd astro && astro dev ps
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

After any declaration YAML change, regenerate the DAG Python file:

```bash
make create-dag-files dag_name={dag_name}
```

---

## Step 3 — Upload artifacts to Forno S3

This step uploads artifacts that Databricks needs to execute jobs in the Forno staging environment.

### Artifact map

| Artifact | Local source | S3 bucket | S3 path |
|---|---|---|---|
| `bietlejuice` wheels (EMR bootstrap) | `dist/*.whl` | `artifacts.s3.forno` | `bi-etl-ejuice/bietlejuice_{core,runtime}-latest-py3-none-any.whl` |
| `bietlejuice` wheels (personal / Databricks) | `dist/*.whl` | `artifacts.s3.forno` | `bi-etl-ejuice-local/{username}/` |
| Spark job scripts | `dags/**/spark_jobs/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice-local/{username}/spark_jobs/` |
| SQL queries | `dags/**/queries/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/queries/` |
| Data quality files | `dags/**/data_quality/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/data_quality/` |
| JSON schemas | `dags/**/schemas/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/schemas/` |
| Qube Python modules | `packages/bietlejuice-runtime/src/bietlejuice/qube/jobs/` | `databricks.s3.forno` | `github-repos/bi-etl-ejuice/qube/jobs/` |
| Init scripts | `packages/bietlejuice-compiler/scripts/emr_init_script.sh`, etc. | `artifacts.s3.forno` | `bi-etl-ejuice/` |

### Decision matrix — upload only what changed

| Changed path | Upload needed | Make target |
|---|---|---|
| `packages/bietlejuice-runtime/src/bietlejuice/qube/jobs/**/*.py` | Qube modules only | `make upload-local-qube-jobs` |
| `packages/*/src/bietlejuice/**/*.py` (non-qube, EMR DAG) | EMR wheels + qube jobs | `make upload-local-wheel-emr upload-local-qube-jobs` |
| `packages/*/src/bietlejuice/**/*.py` (non-qube, Databricks DAG) | Wheel + spark jobs | `make upload-local-package` |
| `dags/**/spark_jobs/**/*.py` | Spark jobs only | `make upload-local-spark-jobs` |
| `dags/**/queries/**/*.sql` | Queries | `make upload-local-queries` |
| `dags/**/data_quality/**/*.yml` | Data quality | `make upload-local-data-quality` |
| `dags/**/schemas/**/*.json` | Schemas | `make upload-local-schemas` |
| `packages/bietlejuice-compiler/scripts/emr_init_script.sh` or `wonka/*.sh` | Init scripts | `make upload-local-init-scripts` |
| Multiple / unsure (EMR pilot) | EMR wheels + qube jobs + init scripts | `make upload-local-wheel-emr upload-local-qube-jobs upload-local-init-scripts` |
| Multiple / unsure (Databricks) | Everything | `make upload-forno-release` |

### Full Forno release

```bash
make upload-forno-release
```

Runs in sequence: wheel build → spark_jobs → queries → data_quality → schemas → qube modules → init scripts. For **EMR pilot DAGs**, also run `make upload-local-wheel-emr` so bootstrap installs the latest wheels from `artifacts.../bi-etl-ejuice/`.

### Individual targets (faster for targeted changes)

```bash
make upload-local-package        # Wheel + spark_jobs (Databricks)
make upload-local-wheel-emr      # EMR bootstrap wheels (*-latest on artifacts bucket)
make upload-local-queries        # SQL queries only
make upload-local-data-quality   # Data quality YAML only
make upload-local-schemas        # JSON schemas only
make upload-local-qube-jobs      # Qube Python modules only
make upload-local-init-scripts   # EMR/Databricks init scripts
```

**Wheel upload**: `local/upload_local_whl_to_s3.py` auto-discovers `bietlejuice_core-*.whl` and `bietlejuice_runtime-*.whl` in `dist/` and uploads them. Run `make build` first to produce the wheels.

**AWS credentials required**: All upload targets call `boto3` or `aws` CLI and need a valid AWS session. QuintoAndar uses **Weep** (Netflix ConsoleMe) for AWS credential brokering.

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

# Export credentials for uploads (S3 artifacts / Databricks repo paths)
eval $(/usr/local/bin/weep export arn:aws:iam::713278628093:role/sso_EngineerFornoStagData_squad)

# For EMR DAG runs, refresh Airflow aws_default separately (DataAndAnalyticsEMRUser_staff)
# docker exec bietlejuice_<hash>-scheduler-1 airflow connections delete aws_default
# docker exec bietlejuice_<hash>-scheduler-1 airflow connections add aws_default \
#   --conn-type aws --conn-extra '{"region_name":"us-east-1","aws_access_key_id":"...","aws_secret_access_key":"...","aws_session_token":"..."}'

# Verify
aws sts get-caller-identity
```

Weep credentials are temporary (~1 hour). Re-run the `eval` command if they expire mid-session.

---

## Step 4 — Live code in Airflow

DAGs, bietlejuice source (**core / airflow / operators / plugins** packages), and compiler
scripts are **bind-mounted** into the Airflow containers via `docker-compose.override.yml`.
Changes you make on disk are reflected live — the scheduler re-parses DAGs within 15–30 seconds.

**No file copying or selective sync is needed.**

The only time you need to restart is when image dependencies change (Dockerfile / package `pyproject.toml` / lock):

```bash
make restart-local-environment
```

If the restart fails with a permission error on `astro/include`:
```bash
sudo chmod 755 ./astro/include
```

---

## Step 5 — Verify DAG via API

**Use the REST API, not `astro dev run dags list`** — the CLI is very slow.

Wait for the scheduler to parse the DAG:

```bash
curl -s -u admin:admin http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}
```

Check the response for:
- `has_import_errors: false` — DAG parses correctly
- `last_parsed_time` — recently updated

If `has_import_errors` is true, check:
```bash
curl -s -u admin:admin http://localhost:8080/api/v1/importErrors
```

List tasks to confirm all expected tasks are present:
```bash
curl -s -u admin:admin "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/tasks" \
  | uv run python -c "import json,sys; data=json.load(sys.stdin); [print(t['task_id']) for t in data['tasks']]; print(f'Total: {data[\"total_entries\"]}')"
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

### Choosing date ranges that match forno data

Forno is a staging environment and may not have recent CDC data. Before triggering, verify what dates are available in the source table:

- Check sample data CSVs if available (e.g. `dags/{domain}/{dag_name}/sample_data/`)
- Or query the source table directly on the Databricks forno workspace

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

## Step 7 — Monitor execution

Poll the DAG run and task instance states. Use exponential backoff:
- First check after 15s (cluster provisioning starts)
- Then every 60s (cluster takes 3–5 min to provision)
- Then every 60–120s (Spark job execution)

**Check DAG run state:**
```bash
curl -s -u admin:admin \
  "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/dagRuns/{dag_run_id}" \
  | uv run python -c "import json,sys; d=json.load(sys.stdin); print(f'DAG state: {d[\"state\"]}')"
```

**Check all task instance states:**
```bash
curl -s -u admin:admin \
  "http://localhost:8080/api/v1/dags/bietlejuice.{dag_name}/dagRuns/{dag_run_id}/taskInstances" \
  | uv run python -c "import json,sys; data=json.load(sys.stdin); [print(f'  {t[\"task_id\"]:45s} state={str(t[\"state\"]):15s} duration={t.get(\"duration\",\"\")}') for t in data['task_instances']]"
```

Typical task execution timeline:
- `execute-job-cluster`: 3–5 min (Databricks cluster provisioning)
- `load-*` tasks: 2–5 min each (Spark job execution)
- `data-quality-*` tasks: 10–30s
- `optimize-*` tasks: 1–5 min (may fail on Forno — see common issues)

Stop polling when `state` is `success` or `failed`.

---

## Step 8 — Inspect failures

[Showing lines 1-300 of 303. Use :301 to continue]