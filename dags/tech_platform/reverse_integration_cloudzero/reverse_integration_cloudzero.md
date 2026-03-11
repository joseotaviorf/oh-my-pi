# Reverse Integration CloudZero DAG

## Description

This DAG sends two kinds of metrics to CloudZero for cost monitoring:

1. **Contracts**: Queries Trino for the number of active rental contracts and sends to CloudZero.
2. **API requests**: Queries Prometheus via Grafana datasource (e.g. Thanos) for the quantity of requests per app and sends to CloudZero as a dimensioned metric.

## Features

- **Trino Query**: Executes a query to count active contracts using Spark
- **Grafana datasource**: Fetches API request counts via Grafana’s Prometheus/Thanos datasource proxy (PromQL instant query)
- **CloudZero Integration**: Sends data via REST API to CloudZero (contracts and API requests)
- **Scheduling**: Runs daily at 6 AM
- **Error Handling**: Includes automatic retry and detailed logging

## Required Configuration

### Databricks Secrets

1. **CLOUDZERO_API_TOKEN**: CloudZero API authentication token configured in Databricks Secrets
2. **GRAFANA_URL** (optional, for API requests): Base URL of Grafana. Default: `https://grafana.apps.shared-prd.habitat.zone`
3. **GRAFANA_DATASOURCE_NAME** (optional): Grafana datasource name (Prometheus/Thanos). Default: `metrics-prod`. If set, the job resolves the UID via Grafana API (requires **GRAFANA_API_TOKEN**).
4. **GRAFANA_DATASOURCE_UID** (optional): Grafana datasource UID. If set, used directly; otherwise UID is resolved from **GRAFANA_DATASOURCE_NAME**.
5. **GRAFANA_API_TOKEN** (required for Grafana): **Grafana service account token** — used for datasource proxy and for resolving UID by name. Create a service account in Grafana (Configuration → Service accounts) and use its token.
6. **PROMETHEUS_REQUESTS_DIMENSION_LABEL** (optional): Label used as CloudZero dimension (e.g. `app`, `api`, `uri`). Default: `app`

The job runs a **range query** over the execution day (00:00–23:59) with **automatic step** (~110 points max); results are aggregated (sum) per app and sent to CloudZero as one value per app per day.

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
├── load_contracts_to_cloudzero (Spark Job) — contracts count from Trino → CloudZero
└── export_reverse-api_requests_count (Spark Job) — API requests from Grafana (Prometheus/Thanos) → CloudZero
```

## CloudZero API Payloads

**Contracts** (metric `quintoandar_contracts_ongoing_rentals`):

```json
{
  "records": [
    {
      "granularity": "MONTHLY",
      "timestamp": "2025-01-01",
      "value": 298594
    }
  ]
}
```

**API requests** (metric `quintoandar_api_requests_count`, one record per application via `custom:API`):

```json
{
  "records": [
    { "granularity": "DAILY", "timestamp": "2025-01-01", "value": 12345, "associated_cost": { "custom:API": "my-service-a" } },
    { "granularity": "DAILY", "timestamp": "2025-01-01", "value": 8901,  "associated_cost": { "custom:API": "my-service-b" } }
  ]
}
```

### Filtering by application in CloudZero

The job sends **one record per application** (one per series from the Prometheus `by (app)` query). Each record uses the dimension `custom:API` with the app name as value.

To filter or group by application in CloudZero:

1. **Unit Cost / Metric stream**: Open the metric `quintoandar_api_requests_count`. Use the dimension **API** (from `custom:API`) to filter or group by application.
2. **Explorer**: In Cost Explorer, add a filter or group-by for the custom dimension **API** so you see cost or unit cost broken down per app.
3. **Custom dimension**: If the dimension does not appear, ensure a Custom Dimension named **API** exists in CloudZero (Settings or CostFormation). The telemetry key `custom:API` maps to that dimension; once it exists, you can filter and segment by it in reports and dashboards.

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
5. **Grafana/Prometheus**: Ensure Grafana is reachable and the datasource (default name `metrics-prod`) points to Thanos/Prometheus. Use a **Grafana service account token** in `GRAFANA_API_TOKEN` for authentication. Adjust `PROMETHEUS_REQUESTS_DIMENSION_LABEL` if your label differs from `app`.
