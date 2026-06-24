## Overview

The Salesforce Pipeline entity tracks the data quality and operational health of Salesforce data pipelines in the Single Station domain. It provides hourly metrics on data volume, latency, schema drift, CDC gaps, Salesforce Appflow connector status, and contract-level quality checks. The primary consumers are the Single Station data engineering team and stakeholders who monitor pipeline reliability, investigate incidents, and validate that data in downstream layers is fresh and complete.

Pipeline execution is evaluated per `target_table` (or `source_table`), per `partition_date` + `partition_hour`. A missing `partition_hour` or `partition_date` for any metric is the canonical signal that the pipeline broke for that table at that hour.

All tables live in the `datalake_sst_metrics` schema (catalog `delta`).

## Glossary and Synonyms

*   **Pipeline broke / pipeline down** → no row for a given `source_table` / `target_table` at the expected `partition_date` + `partition_hour`
    
*   **Appflow** → AWS AppFlow connector used to ingest Salesforce data; health tracked via `appflow_status` (status must be `'Active'`; any other value triggers the recovery flow)
    
*   **Recovery flow** → automated remediation triggered when Appflow status ≠ `'Active'`
    
*   **CDC** → Change Data Capture; gaps tracked in `cdc_pipeline_missing_events`
    
*   **Latency / delay** → time (hours or minutes, per `unit` column) between source and target layer; measured in `pipeline_events_latency`
    
*   **window_size** → rolling window (in hours) used to compute moving averages and z-scores in `pipeline_stability`; also present in `stability` (older table, same schema)
    
*   **SST** → abbreviation for Single Station
    
*   **Schema drift / new columns** → unexpected columns added to a source table; tracked in `table_metadata.new_cols`
    

## Tables

| You need... | Use this table |
| --- | --- |
| Volume anomaly detection (z-score, stddev, moving avg) per table per hour | `datalake_sst_metrics.pipeline_stability` — grain: 1 row per `source_table` + `partition_date` + `partition_hour` + `window_size`; use `environment = 'prod'` |
| Raw hourly row count per table | `datalake_sst_metrics.events_volume` — grain: 1 row per `source_table` + `partition_date` + `partition_hour`; simpler than `pipeline_stability` when you only need `row_count` |
| Row count broken down by event type | `datalake_sst_metrics.events_type_volume` — same as `events_volume` plus `event_type` column |
| Latency / delay from source to target layer | `datalake_sst_metrics.pipeline_events_latency` — grain: 1 row per `target_table` + `partition_date` + `partition_hour`; includes `average_delay`, `p50`/`p90`/`p95`/`p99`, `unit`, `source_layer`, `target_layer` |
| CDC gaps — missing events in Change Data Capture | `datalake_sst_metrics.cdc_pipeline_missing_events` — grain: 1 row per `target_table` + `partition_date` + `partition_hour`; check `total_events_missing > 0` |
| Schema drift — new columns added to a source table | `datalake_sst_metrics.table_metadata` — grain: 1 row per `source_table` + `partition_date` + `partition_hour`; `new_cols` (array as VARCHAR) + `new_cols_count` |
| Contract-level pipeline freshness checks | `datalake_sst_metrics.contract_quality_checks` — grain: 1 row per `table_name` + `metric_name`; `status` column + `last_row_timestamp` + `threshold_time_hours` |
| Salesforce Appflow connector health | `datalake_sst_metrics.appflow_status` — _do not use!_ not currently registered in Trino (delta/hive) because it's still under development. |
| Salesforce API logs | `datalake_sst_metrics.salesforce_api_logs` — ⚠️ same caveat as `appflow_status`; not found in Trino at time of writing. |
| (Legacy) Volume stability | `datalake_sst_metrics.stability` — identical schema to `pipeline_stability`; likely an older version. Prefer `pipeline_stability`. |

**Critical rules:**

*   Always filter `environment = 'prod'` in `pipeline_stability`, `events_volume`, `events_type_volume`, and `table_metadata` to exclude test/staging runs.
    
*   `pipeline_events_latency` uses `target_table` (not `source_table`) as the grain key; it also has a `window_size` column absent from `events_volume` / `events_type_volume`.
    
*   `cdc_pipeline_missing_events` uses `env` (not `environment`) — note the column name difference.
    
*   `partition_date` and `partition_hour` are both `VARCHAR` across all tables. Cast to date/integer as needed: `CAST(partition_date AS DATE)`, `CAST(partition_hour AS INTEGER)`.
    
*   A missing row for a `(source_table, partition_date, partition_hour)` combination means the pipeline did not run — this is itself a failure signal, not a NULL value.
    

## Key Metrics

*   **Row count** (`events_volume.row_count` / `pipeline_stability.row_count`) — number of records processed for a given table and hour
    
*   **Volume % delta** (`pipeline_stability.volume_pct_delta`) — percentage change vs. the rolling average; large deviations signal anomalies
    
*   **Z-score** (`pipeline_stability.z_score`) — statistical anomaly score; high absolute values indicate unusual volume
    
*   **Moving average** (`pipeline_stability.moving_avg`) — baseline expected row count over `window_size` hours
    
*   **Average delay** (`pipeline_events_latency.average_delay`) — mean latency from source to target layer, in the unit specified by `pipeline_events_latency.unit`
    
*   **P90 / P95 / P99 latency** (`pipeline_events_latency.p90/p95/p99`) — tail latency percentiles; critical for SLA monitoring
    
*   **Missing events** (`cdc_pipeline_missing_events.total_events_missing`) — total CDC events not captured; `> 0` is an alert
    
*   **Unique records missing** (`cdc_pipeline_missing_events.unique_id_record_missing`) — distinct records with missing CDC events
    
*   **New columns count** (`table_metadata.new_cols_count`) — number of unexpected new columns detected in a source table that hour
    
*   **Contract status** (`contract_quality_checks.status`) — pass/fail string for each quality check per table
    

## Relationships with Other Entities

### pipeline_stability ↔ events_volume (N:1 per hour)

*   Both share `source_table + partition_date + partition_hour` as the join key.
    
*   `pipeline_stability` has multiple rows per hour (one per `window_size`); filter to a single `window_size` before joining.
    

sql

```sql
SELECT
  ev.source_table,
  ev.partition_date,
  ev.partition_hour,
  ev.row_count,
  ps.z_score,
  ps.moving_avg
FROM datalake_sst_metrics.events_volume ev
JOIN datalake_sst_metrics.pipeline_stability ps
  ON ev.source_table    = ps.source_table
 AND ev.partition_date  = ps.partition_date
 AND ev.partition_hour  = ps.partition_hour
 AND ps.window_size     = 24          -- pick one window; 24h is a common default
WHERE ev.environment = 'prod'
  AND ps.environment = 'prod'

```

### pipeline_events_latency ↔ cdc_pipeline_missing_events (1:1 per target_table per hour)

*   Both use `target_table + partition_date + partition_hour`.
    
*   Left-join from latency onto missing-events to combine delay and gap signals.
    

sql

```sql
SELECT
  l.target_table,
  l.partition_date,
  l.partition_hour,
  l.average_delay,
  l.unit,
  COALESCE(m.total_events_missing, 0) AS total_events_missing
FROM datalake_sst_metrics.pipeline_events_latency l
LEFT JOIN datalake_sst_metrics.cdc_pipeline_missing_events m
  ON l.target_table   = m.target_table
 AND l.partition_date = m.partition_date
 AND l.partition_hour = m.partition_hour

```

## Dos and Don'ts

**Do:**

*   Filter `environment = 'prod'` on every query against `pipeline_stability`, `events_volume`, `events_type_volume`, and `table_metadata`.
    
*   Use the absence of a row (no `partition_date` / `partition_hour` for a table) as the primary pipeline-broke signal — do not rely solely on NULL columns.
    
*   When checking Appflow health, filter `status != 'Active'` and alert on any non-active result.
    
*   Use `pipeline_events_latency` for SLA/latency questions — it has percentile columns (`p50`/`p90`/`p95`/`p99`) that `events_volume` does not.
    
*   Cast `partition_date` and `partition_hour` explicitly: they are `VARCHAR` in all tables.
    
*   Pick a consistent `window_size` when querying `pipeline_stability` across multiple rows.
    
*   Use `table_metadata` to answer "what new columns appeared in table X" — check `new_cols_count > 0` and read the `new_cols` array.
    

**Don't:**

*   Don't query `stability` for new analyses — it is the legacy version of `pipeline_stability`. Prefer `pipeline_stability`.
    
*   Don't use `appflow_status` or `salesforce_api_logs` yet, they are currently not available in Trino.
    
*   Don't use `pipeline_events_latency` with `source_table` as the key — this table uses `target_table` (the destination layer table), not the source.
    
*   Don't join `cdc_pipeline_missing_events` using `environment` — this table uses `env` (shorter column name), unlike the rest of the schema.
    
*   Don't compare raw `average_delay` values across tables without checking the `unit` column — latency may be in hours or minutes depending on the pipeline.
    
*   Don't treat `z_score = 0` as healthy without also checking `has_historical_data = true`; a table with no history will show `z_score = 0` trivially.
    

## Golden Queries

### Query 1 — Tables currently experiencing delay (latest hour)

Returns all tables with above-average latency in the most recent available partition.

sql

```sql
WITH latest AS (
  SELECT MAX(partition_date) AS max_date
  FROM datalake_sst_metrics.pipeline_events_latency
)
SELECT
  l.target_table,
  l.partition_date,
  l.partition_hour,
  l.average_delay,
  l.p90,
  l.p99,
  l.unit,
  l.source_layer,
  l.target_layer
FROM datalake_sst_metrics.pipeline_events_latency l
JOIN latest ON l.partition_date = latest.max_date
ORDER BY l.average_delay DESC
LIMIT 50

```

### Query 2 — Pipeline stability: volume anomalies in the last 24 hours

Surfaces tables with z-score outside ±2 in the last day (24h window).

sql

```sql
SELECT
  source_table,
  partition_date,
  partition_hour,
  row_count,
  moving_avg,
  z_score,
  volume_pct_delta
FROM datalake_sst_metrics.pipeline_stability
WHERE CAST(partition_date AS DATE) >= CURRENT_DATE - INTERVAL '1' DAY
  AND environment = 'prod'
  AND window_size = 24
  AND has_historical_data = true
  AND ABS(z_score) > 2
ORDER BY ABS(z_score) DESC
LIMIT 50

```

### Query 3 — CDC gaps: tables with missing events in the last 7 days

sql

```sql
SELECT
  target_table,
  partition_date,
  partition_hour,
  total_events_missing,
  unique_id_record_missing
FROM datalake_sst_metrics.cdc_pipeline_missing_events
WHERE CAST(partition_date AS DATE) >= CURRENT_DATE - INTERVAL '7' DAY
  AND total_events_missing > 0
ORDER BY partition_date DESC, total_events_missing DESC
LIMIT 100

```

## DataHub catalog

- **Data Product:** `urn:li:dataProduct:salesforce-sst-pipeline`

