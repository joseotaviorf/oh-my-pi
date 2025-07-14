# Reverse Integration CloudZero DAG

This directory contains the DAG to query contracts in Trino and send to CloudZero using Spark jobs.

## Files

- `reverse_integration_cloudzero_declaration.yml` - DAG configuration
- `reverse_integration_cloudzero.md` - Detailed documentation
- `spark_jobs/load_contracts_to_cloudzero.py` - Main Spark job
- `queries/contracts_count.sql` - SQL query example
- `README.md` - This file

## Configuration

### 1. Databricks Secrets
Configure the `CLOUDZERO_API_TOKEN` secret in Databricks with the CloudZero API token.

### 2. SQL Query
The SQL query in the Spark job `load_contracts_to_cloudzero.py` is already configured to use the real project tables.

## Usage

The DAG runs automatically every day at 6 AM. For manual execution:

1. Access the Airflow UI
2. Navigate to the DAG `tech_platform.reverse_integration_cloudzero`
3. Click "Trigger DAG"

## Monitoring

Check the logs of the `load_contracts_to_cloudzero` task to monitor execution.
