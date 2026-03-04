---
name: upload-to-forno
description: Detect what code changed and upload only the relevant artifacts to the forno (staging) S3/Databricks environment for local testing. Handles wheel, Spark jobs, and Qube jobs. Use when the user wants to test their changes on forno without merging, or asks "how do I test this on Databricks?".
---

# Upload to Forno

## When to use

- After modifying `bietlejuice/` code and wanting to test it on a Databricks forno cluster
- After modifying a Spark job (`bietlejuice/base/spark/`) or a Qube job (`bietlejuice/qube/jobs/`)
- User says "how do I test this on forno", "upload to Databricks", or "test my changes on staging"

---

## Step 0 — Prerequisites

Verify the following before uploading:

```bash
# AWS credentials must be configured (for S3 upload)
aws sts get-caller-identity

# GITHUB_TOKEN must be set (for wheel build with private packages)
echo $GITHUB_TOKEN
```

If `aws sts` fails, the user needs to refresh their AWS SSO session:
```bash
aws sso login --profile forno   # adjust profile name as needed
```

If `GITHUB_TOKEN` is not set, refer to the `setup-local-environment` skill.

---

## Step 1 — Detect what changed

Run a git diff to categorize the changes:

```bash
git diff --name-only origin/master HEAD
```

Then apply this decision table:

| Changed path pattern | Upload needed | Make target |
|----------------------|--------------|-------------|
| `bietlejuice/qube/jobs/**/*.py` | Qube jobs only | `upload-local-qube-jobs` |
| `bietlejuice/**/*.py` (any other path) | Full wheel + Spark jobs | `upload-local-wheel` + `upload-local-spark-jobs` |
| `dags/**/*_declaration.yml` | DAG files only (no upload) | `make create-dag-files` |
| `queries/**/*.sql` | No upload needed | — |
| `scripts/**/*.py` | No upload needed | — |

**Decision rules:**
- If ONLY `bietlejuice/qube/jobs/` files changed → run `upload-local-qube-jobs` only.
- If any other `bietlejuice/` files changed → run `upload-local-wheel` AND `upload-local-spark-jobs`.
- If both qube jobs AND other bietlejuice files changed → run all three: `upload-local-wheel`, `upload-local-spark-jobs`, `upload-local-qube-jobs`.
- If no `bietlejuice/` files changed → no S3 upload needed; skip to Step 3.

Present the plan to the user before uploading so they can confirm.

---

## Step 2 — Run the upload commands

### Qube jobs only

```bash
make upload-local-qube-jobs
```

Uploads all `bietlejuice/qube/jobs/` Python files to forno S3. Databricks picks up the latest code on the next cluster start or job run. Fast (~5 seconds).

### Full package (wheel + Spark jobs)

Run in sequence — order matters:

```bash
# 1. Upload Spark job scripts to S3
make upload-local-spark-jobs

# 2. Build and upload the bietlejuice wheel to S3
make upload-local-wheel
```

`upload-local-wheel` runs `python3 -m setup sdist bdist_wheel` then uploads the `.whl` to forno S3 (`databricks.s3.forno.data.quintoandar.com.br`). Databricks clusters must be restarted to pick up the new wheel. Warn the user.

### All at once (when both changed)

```bash
make upload-local-spark-jobs
make upload-local-wheel
make upload-local-qube-jobs
```

---

## Step 3 — Trigger the DAG on forno

After uploading, guide the user to test their changes:

### Option A — Trigger via local Airflow UI

If the local environment is running (see `setup-local-environment` skill):
1. Open http://localhost:8080
2. Find the DAG by name
3. Toggle it on and trigger a manual run with the desired `load_start_date` / `load_end_date`

### Option B — Trigger via forno Airflow

1. Open the forno Airflow UI (ask the user for the URL if unknown, typically an internal QuintoAndar link)
2. Find the DAG, trigger a manual run

### Option C — Direct Databricks job (for Spark/Qube jobs)

For quick iteration without the Airflow layer:
1. Open the Databricks forno workspace
2. Navigate to **Workflows > Jobs** and find the job matching the DAG/table name
3. Click **Run now** with the desired parameters

---

## Step 4 — Confirm Databricks picked up the new code

After a cluster restart (required for wheel changes), verify the new code is active:

```bash
# On the Databricks cluster, check installed version
pip show bietlejuice
```

The version should match the one in `setup.py` or the local wheel build output.

For Qube jobs (no cluster restart needed), the new `.py` files are downloaded at job start — no extra check required.

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `NoCredentialsError` or `ExpiredToken` | AWS session expired | Run `aws sso login` |
| `403 Forbidden` on S3 upload | Wrong AWS profile or bucket | Check `local/upload_local_whl_to_s3.py` for the target bucket and verify your profile has write access |
| Wheel build fails with package import error | Missing `GITHUB_TOKEN` for private deps | Export `GITHUB_TOKEN` and retry |
| Databricks job uses old code after upload | Cluster not restarted (wheel change) | Restart the Databricks cluster before re-running the job |
| Qube job still runs old code | Job was already queued before upload | Wait for the current job to finish, then re-trigger |

---

## Checklist

- [ ] AWS credentials valid (`aws sts get-caller-identity` succeeds)
- [ ] `GITHUB_TOKEN` exported (if uploading the wheel)
- [ ] Correct upload targets identified from `git diff`
- [ ] Upload commands completed without S3 errors
- [ ] Databricks cluster restarted if wheel was changed
- [ ] DAG or Databricks job triggered on forno to validate the change
