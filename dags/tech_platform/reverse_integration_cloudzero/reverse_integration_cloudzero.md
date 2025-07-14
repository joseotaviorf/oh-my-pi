# Reverse Integration CloudZero DAG

## Description

This DAG queries Trino to get the number of active rental contracts and sends this data to the CloudZero API for cost monitoring.

## Features

- **Trino Query**: Executes a query to count active contracts using Spark
- **CloudZero Integration**: Sends data via REST API to CloudZero
- **Scheduling**: Runs daily at 6 AM
- **Error Handling**: Includes automatic retry and detailed logging

## Required Configuration

### Databricks Secrets

1. **CLOUDZERO_API_TOKEN**: CloudZero API authentication token configured in Databricks Secrets

### SQL Query

The SQL query in the Spark job `load_contracts_to_cloudzero.py` uses the real project tables:

```sql
SELECT
  count(distinct dc.sk_contract) AS contracts_count
FROM dw_rent.dim_contract dc
WHERE dc.status in ('Ativo', 'Finalizado')
  AND dc.type <> 'DealOnly'
  AND date(coalesce(dc.dt_start, dc.dt_entrance)) <= current_date
  AND (dc.dt_annulment IS NULL OR date(dc.dt_annulment) >= current_date)
```

## DAG Structure

```
tech_platform.reverse_integration_cloudzero
└── load_contracts_to_cloudzero (Spark Job)
```

## CloudZero API Payload

The DAG sends data in the format:

```json
{
  "records": [
    {
      "granularity": "DAILY",
      "timestamp": "2025-01-01",
      "value": 298594
    }
  ]
}
```

## Monitoring

- Detailed logs for debugging
- Automatic retry in case of failure
- API response validation
- Specific error handling

## Troubleshooting

1. **Trino connection error**: Check Databricks cluster configuration
2. **CloudZero authentication error**: Check `CLOUDZERO_API_TOKEN` secret in Databricks
3. **Query with no results**: Check if the SQL query is correct
4. **API error**: Check logs for CloudZero response details
