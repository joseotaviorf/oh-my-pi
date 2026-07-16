# amplitude_optimization — clean v2 twin ops runbook

Manual twin for unlocking `amplitude_new` clean throughput. Code lives under
`dags/growth/amplitude_optimization/`.

## What this DAG does

| Item | Value |
|------|--------|
| Schedule | `null` (manual only) |
| Datasets | none (`datasets = None`) |
| Reads | `datalake_amplitude_new_raw.events` (Delta only) |
| Writes | `datalake_amplitude_events_v2_clean.events` |
| Partitions | `id_app, year, month, day` (+ ZORDER `event_type`) |
| Cluster | `consolidation_l_memory_cluster`, 5 workers, Spot |
| Coverage | dates **≥ 2026-06-07** only |

Production `amplitude_new` and the consumer VIEW `datalake_amplitude_clean.events` stay on v1 until cutover.

## Backfill from June (`backfill-from-june`)

For each date `D` from `2026-06-07` through yesterday:

1. Confirm `bietlejuice.amplitude_new` succeeded for `D` (raw + clean).
2. Trigger a manual DAG run of `bietlejuice.amplitude_optimization` with logical date / data interval for `D` (same load window params as prod: `load_start_date = D-1`, `load_end_date = D` via declaration defaults).
3. Wait for `load-clean-events` (+ optimize) to succeed.
4. Optional parity check:

```sql
SELECT 'v1' AS src, COUNT(*) AS n
FROM quintoandar_prod.datalake_amplitude_events_clean.events
WHERE year = YEAR(DATE 'D') AND month = MONTH(DATE 'D') AND day = DAY(DATE 'D')
UNION ALL
SELECT 'v2', COUNT(*)
FROM quintoandar_prod.datalake_amplitude_events_v2_clean.events
WHERE year = YEAR(DATE 'D') AND month = MONTH(DATE 'D') AND day = DAY(DATE 'D');
```

Prefer starting with 1–2 recent successful prod days before walking history.

## Prove daily (`prove-daily`)

After a few twin runs, compare against prod `load-clean-events` in
`hive.dw_databricks_health.fact_databricks_task_run`:

- Twin wall-clock << prod (expect large drop)
- Mid-run CPU busy higher / wait lower on Databricks Metrics
- Row counts match for the same `D`
- `DESCRIBE DETAIL …_v2_clean.events` shows partitions without `event_type` and far fewer files per day

Do **not** cut over until this holds for several days.

## Cutover (`declaration-cutover`) — do only after prove

Single brief maintenance window:

1. Pause `bietlejuice.amplitude_new` in Airflow.
2. Update [`amplitude_new_declaration.yml`](../../dags/growth/amplitude_new/amplitude_new_declaration.yml):

```yaml
workflow:
  type: custom_ingestion
  layer: raw
  load_spark_job: load_amplitude_new_raw
  custom_schema: amplitude_events_v2
  execution_timeout_hours: 5
  incremental_optimize: true
  # ... keep spark_job_arguments / extra_query_template_params ...
  tables_customization:
    events:
      extraction_type: incremental
      partitions: ["id_app", "year", "month", "day"]
      z_order_by: ["event_type"]
      extra_spark_job_arguments:
        - "{{ data_interval_start | ds }}"
      run_optimize: true
      run_vacuum: true
      has_hive_sync: false
```

3. On cluster YAML, add write-time coalescing (optional but recommended):

```yaml
spark_conf:
  spark.databricks.delta.optimizeWrite.enabled: "true"
```

4. `make create-dag-files dag_name=amplitude_new` and merge.

5. Swap the consumer view in Databricks:

```sql
CREATE OR REPLACE VIEW quintoandar_prod.datalake_amplitude_clean.events
AS SELECT * FROM quintoandar_prod.datalake_amplitude_events_v2_clean.events;
```

6. Resume `amplitude_new` and trigger one manual day.
7. Retire / delete `amplitude_optimization` once prod is stable.

**Rollback:** repoint the VIEW to `datalake_amplitude_events_clean.events` and revert the declaration.

## Post-cutover monitor (`validate-monitor`)

For one week:

- `load-clean-events` duration and timeout risk
- Worker CPU busy/wait pattern (no long low-busy plateau)
- v2 `numFiles` growth rate (`DESCRIBE DETAIL`)
- `optimize-clean-*` duration should be minutes (real OPTIMIZE), not ~15s
- Consumer queries via `datalake_amplitude_clean.events` unchanged

Then archive/drop the old physical v1 table when safe.
