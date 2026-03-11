# Reverse Integration CloudZero DAG

This directory contains the DAG that sends metrics to CloudZero: contracts count from Trino and API request counts from Prometheus via Grafana datasource.

## Files

- `reverse_integration_cloudzero_declaration.yml` - DAG configuration
- `reverse_integration_cloudzero.md` - Detailed documentation
- `spark_jobs/load_contracts_to_cloudzero.py` - Spark job: contracts from Trino → CloudZero
- `spark_jobs/load_api_requests_to_cloudzero.py` - Spark job: API requests from Thanos → CloudZero
- `queries/reverse/contracts_count.sql` - SQL for contracts count
- `README.md` - This file

## Configuration

### 1. Databricks Secrets
- **CLOUDZERO_API_TOKEN**: CloudZero API token (required for both jobs).
- **GRAFANA_URL** (optional): Base URL of Grafana; default is `https://grafana.apps.shared-prd.habitat.zone`.
- **GRAFANA_DATASOURCE_NAME** (optional): Datasource name in Grafana; default is `metrics-prod`. UID is resolved via API when not using UID.
- **GRAFANA_DATASOURCE_UID** (optional): Datasource UID; if set, name lookup is skipped.
- **GRAFANA_API_TOKEN**: **Grafana service account token** (required for auth and for resolving datasource by name).
- **PROMETHEUS_REQUESTS_DIMENSION_LABEL** (optional): Label for CloudZero dimension (default: `app`).

### 2. SQL Query
The contracts Spark job reads from the reverse table built by `queries/reverse/contracts_count.sql`.

## Usage

The DAG runs automatically every day at 6 AM. For manual execution:

1. Access the Airflow UI
2. Navigate to the DAG `tech_platform.reverse_integration_cloudzero`
3. Click "Trigger DAG"

## Monitoring

Check the logs of the `load_contracts_to_cloudzero` and `export_reverse-api_requests_count` tasks to monitor execution.
