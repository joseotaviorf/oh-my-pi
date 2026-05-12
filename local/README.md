# Local Airflow Environment (Astro CLI)

> **For full setup instructions** (uv, Python, credentials, dev container), see the **[root README](../README.md)**.
> This file covers Astro-specific operational commands only.

## Prerequisites

- [Astro CLI](https://www.astronomer.io/docs/astro/cli/install-cli/) installed (`brew install astro` on macOS)
- Docker running — see [Colima setup](https://docs.google.com/document/d/1S1nonH-HBK9-CUX19YczVR2abYchwtGzBDhzclMk7W8/edit?tab=t.0#heading=h.20gk8wb7m9e1) or QuintoAndar's [local-setup](https://github.com/quintoandar/local-setup)
- `GITHUB_TOKEN` and `DATABRICKS_TOKEN` set in your shell (run `make setup-local-variables` once)

## Running Airflow

All commands run from the **repository root**.

### 1. Generate DAG files

```bash
make create-dag-files
# or for a specific DAG:
make create-dag-files dag_name=your_dag_name
```

### 2. Start Airflow

```bash
make run-local-environment
```

Access the webserver at **https://localhost:8080**.

### 3. Restart / Stop / Kill

```bash
make restart-local-environment   # rebuild image + restart containers
make stop-local-environment      # stop containers, preserve state
make kill-local-environment      # stop containers + delete local metadata DB
```

## Deploying local artifacts to S3 (Forno)

```bash
make upload-local-spark-jobs     # upload Spark jobs
make upload-local-package        # build + upload wheel
make upload-local-queries        # upload SQL queries
make upload-local-data-quality   # upload data quality specs
make upload-local-schemas        # upload JSON schemas
make upload-local-qube-jobs      # upload Qube job files
```
