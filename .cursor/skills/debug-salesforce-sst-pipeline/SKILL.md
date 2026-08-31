---
name: debug-salesforce-sst-pipeline
description: Diagnose Salesforce SST ingestion, AppFlow recovery, CDC gaps, DLQ dead-letter replay, and recovered-row volume. Use when investigating salesforce_cdc, datalake_sst_metrics, RECOVERY events, DLQ_RECOVERY, missing Salesforce rows, or DLQ tasks.
---

# Debug Salesforce SST Pipeline

Use this workflow for `bietlejuice.salesforce_cdc` incidents and volume questions.

## Read first

- `docs/runbooks/support_journey_pipeline_runbook.md`
- `docs/llm_context/domain_entities/salesforce_sst_pipeline.md`

Use the `trino` skill only to execute SQL after this skill has selected and bounded the
query.

## Distinguish the two recovery paths

1. **AppFlow fallback** — `salesforce/recovery_flow.py` fetches an hour through the
   Salesforce API when AppFlow is not `Active`. Lake rows use `event_type = 'RECOVERY'`.
2. **DLQ replay** — `salesforce/dlq.py` runs at the end of each event lineage, after the
   metrics tasks. It finds IDs present in raw but missing from clean, fetches current
   records as lake `event_type = 'RECOVERY'`, upserts raw, and replays their complete raw
   CDC history into clean.

## DLQ volume

DLQ appends to `datalake_sst_metrics.events_type_volume` with a **metric-only**
`event_type = 'DLQ_RECOVERY'` (lake rows stay `RECOVERY`). Grain is
`source_table + partition_date + partition_hour + event_type`. Filter
`environment = 'prod'`.

- `layer = 'raw'`: API rows upserted into raw.
- `layer = 'clean'`: CDC history rows replayed into clean (can exceed raw).

The pre-DLQ CDC types (`CREATE`/`UPDATE`/`DELETE`/`RECOVERY`) in the same table do **not**
include that hour's DLQ work. Do not use `event_type = 'RECOVERY'` as the DLQ volume
signal. Both layers are written on **every** run, so `row_count = 0` means there was no gap
that hour; an **absent** row means the `dlq_events_*` Airflow task did not run.

```sql
SELECT
  source_table,
  partition_date,
  partition_hour,
  layer,
  row_count,
  _write_timestamp
FROM datalake_sst_metrics.events_type_volume
WHERE environment = 'prod'
  AND event_type = 'DLQ_RECOVERY'
  AND CAST(partition_date AS DATE) >= CURRENT_DATE - INTERVAL '7' DAY
ORDER BY partition_date DESC, CAST(partition_hour AS INTEGER) DESC
LIMIT 100
```

## Interpret alongside the pre-DLQ gap

`datalake_sst_metrics.cdc_pipeline_missing_events` is a snapshot taken **before** the DLQ
for that hour, so `total_events_missing > 0` there is the gap the DLQ was then asked to
fix — not necessarily lost data. Compare it with the `DLQ_RECOVERY` counts for the same
hour, but do not expect the numbers to line up:

- missing-event rows count raw events absent from clean at snapshot time;
- raw `DLQ_RECOVERY` counts Salesforce API records returned;
- clean `DLQ_RECOVERY` counts replayed CDC history rows.

If the gap is positive, read the matching `dlq_events_*` task logs for an early exit, API
response, or write failure. `DLQ_RECOVERY` rows with `row_count = 0` alongside a positive
gap mean the DLQ found no IDs to fetch — suspect `retrieve_missing_events` scoping or a
raw-side partition problem rather than the API.

## Code map

- DAG order: `dags/support_and_service/salesforce_cdc/salesforce_cdc.py`
- DLQ replay: `packages/bietlejuice-runtime/src/bietlejuice/base/sst/pipelines/salesforce/dlq.py`
- AppFlow fallback: `packages/bietlejuice-runtime/src/bietlejuice/base/sst/pipelines/salesforce/recovery_flow.py`
- pre-DLQ gap metric: `packages/bietlejuice-runtime/src/bietlejuice/base/sst/pipelines/salesforce/metrics/missing_events.py`
- shared volume writer: `packages/bietlejuice-runtime/src/bietlejuice/base/sst/core/observability/metrics.py`
