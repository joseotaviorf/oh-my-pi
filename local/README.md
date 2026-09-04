# Local helpers (non-Airflow)

> **Local Airflow** lives under [`astro/`](../astro/README.md) — see the root
> [`README`](../README.md) and `make run-local-environment` / related Makefile targets.

This folder holds standalone developer tooling:

- **`emr_monitor/`** — EMR cluster monitoring app (own [`README`](emr_monitor/README.md)).
- **`etl_gantt/`** — upstream ETL timelines (median time-of-day) via Trino (own [`README`](etl_gantt/README.md)).
- **`upload_local_spark_jobs_to_s3.py`** / **`upload_local_whl_to_s3.py`** — push local
  artifacts to the Forno S3 buckets, used by the `make upload-local-*` targets below.

## Deploying local artifacts to S3 (Forno)

```bash
make upload-local-spark-jobs     # upload Spark jobs
make upload-local-package        # build + upload wheel
make upload-local-queries        # upload SQL queries
make upload-local-data-quality   # upload data quality specs
make upload-local-schemas        # upload JSON schemas
make upload-local-qube-jobs      # upload Qube job files
```
