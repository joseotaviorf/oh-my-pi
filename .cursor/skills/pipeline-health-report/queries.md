# Pipeline health — queries

Substitute `<LINE_NAME>`, `<DT_FROM>`, `<DT_TO>` (`YYYY-MM-DD`, BRT dates), and IN-lists of team `id_dag`s. Catalog `hive`. Always filter partition columns.

Prefer Trino MCP `execute_query`. Fallback: `uv run --script .cursor/skills/trino/scripts/execute_trino.py --host "${TRINO_HOST:-trino.apps.data-prd.habitat.zone}" --catalog hive --external-auth --query '…'`.

**CAST every DATE/TIMESTAMP to `varchar`** in the SELECT list when using `execute_trino.py` (the script's `json.dumps` cannot serialize Python `date`).

Do not `SELECT *`. Bound result sets (`LIMIT` 5000 on row-level extracts). Quote reserved identifiers (`"table"`).

**Dependency chain is mandatory before any delay cause.** For every missed consumer, read `dags/dependencies.yaml` first; then query producer SLA. Same-day `is_outside_sla` on a DAG that is not a YAML producer is not cascade.

SLA root-cause also uses Drive postmortems — folder, search, and match rules in [postmortems.md](postmortems.md) (not SQL).

---

## Line lookup

```sql
SELECT
    id_line,
    line_name,
    is_data_line
FROM hive.datalake_pipeline.line
WHERE lower(line_name) LIKE lower('%<LINE_TOKEN>%')
LIMIT 50
```

If multiple rows, pick the exact `line_name` from [aliases.md](aliases.md) or ask the user.

---

## Team DAG inventory

```sql
SELECT
    d.id_dag,
    d.layer,
    d.is_datamart,
    d.brt_sla_hour,
    d.is_paused,
    d.is_active
FROM hive.datalake_pipeline.dag AS d
WHERE d.line_name = '<LINE_NAME>'
    AND d.is_active = TRUE
LIMIT 5000
```

`id_dag` is `bietlejuice.<dag_name>`. Grafana `cluster_name` is usually the bare `<dag_name>`.

---

## Daily SLA (DW)

`fact_pipeline_metrics` is partitioned by snapshot date. `sla` is already the line-level percentage.

```sql
SELECT
    CAST(f.dt_snapshot AS varchar) AS dt_snapshot,
    l.line_name,
    f.sla,
    f.total_dags_inside_sla,
    f.total_dags_outside_sla,
    f.total_dags_null_sla,
    f.total_dags_ignoring_list,
    f.total_intraday_dags,
    f.total_active_unpaused_dags,
    f.total_failed_dags
FROM hive.dw_pipeline.fact_pipeline_metrics AS f
INNER JOIN hive.dw_pipeline.dim_line AS l
    ON l.sk_line = f.sk_line
WHERE l.line_name = '<LINE_NAME>'
    AND f.dt_snapshot >= DATE '<DT_FROM>'
    AND f.dt_snapshot <= DATE '<DT_TO>'
    AND f.year >= YEAR(DATE '<DT_FROM>')
    AND f.year <= YEAR(DATE '<DT_TO>')
ORDER BY f.dt_snapshot
LIMIT 50
```

### Fallback from enrich (same formula as `fact_pipeline_metrics.sql`)

Use when a snapshot day is missing in DW. Cast counts to `DOUBLE` or the ratio is 0.

```sql
SELECT
    CAST(ds.dt_snapshot AS varchar) AS dt_snapshot,
    ROUND(
        100.0 * (
            CAST(COUNT(DISTINCT ds.id_dag) FILTER (
                WHERE ds.is_inside_sla = TRUE
                    AND COALESCE(ds.is_intraday_dag, FALSE) = FALSE
                    AND (
                        (
                            ds.is_active_and_unpaused = TRUE
                            AND COALESCE(ds.is_in_ignoring_list, FALSE) = FALSE
                        )
                        OR ds.is_special_scheduler_executed = TRUE
                    )
            ) AS DOUBLE)
            / NULLIF(
                CAST(COUNT(DISTINCT ds.id_dag) FILTER (
                    WHERE COALESCE(ds.is_intraday_dag, FALSE) = FALSE
                        AND (
                            (
                                ds.is_active_and_unpaused = TRUE
                                AND COALESCE(ds.is_in_ignoring_list, FALSE) = FALSE
                            )
                            OR ds.is_special_scheduler_executed = TRUE
                        )
                ) AS DOUBLE),
                0
            )
        ),
        1
    ) AS sla,
    COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_outside_sla = TRUE) AS total_dags_outside_sla
FROM hive.datalake_pipeline.dag_sla_information AS ds
INNER JOIN hive.datalake_pipeline.dag AS d
    ON d.id_dag = ds.id_dag
WHERE d.line_name = '<LINE_NAME>'
    AND ds.dt_snapshot >= DATE '<DT_FROM>'
    AND ds.dt_snapshot <= DATE '<DT_TO>'
    AND ds.year >= YEAR(DATE '<DT_FROM>')
    AND ds.year <= YEAR(DATE '<DT_TO>')
GROUP BY ds.dt_snapshot
ORDER BY ds.dt_snapshot
LIMIT 50
```

---

## Missed-SLA DAGs (eligible misses only)

```sql
SELECT
    CAST(ds.dt_snapshot AS varchar) AS dt_snapshot,
    ds.id_dag,
    d.layer,
    d.is_datamart,
    d.brt_sla_hour,
    ds.is_run_successful,
    ds.is_run_failed,
    ds.is_manual_run,
    CAST(ds.ts_first_execution_success_brt AS varchar) AS ts_first_execution_success_brt,
    CAST(ds.ts_last_table_task_successful_brt AS varchar) AS ts_last_table_task_successful_brt,
    CAST(ds.dt_run AS varchar) AS dt_run
FROM hive.datalake_pipeline.dag_sla_information AS ds
INNER JOIN hive.datalake_pipeline.dag AS d
    ON d.id_dag = ds.id_dag
WHERE d.line_name = '<LINE_NAME>'
    AND ds.is_outside_sla = TRUE
    AND COALESCE(ds.is_intraday_dag, FALSE) = FALSE
    AND COALESCE(ds.is_in_ignoring_list, FALSE) = FALSE
    AND ds.dt_snapshot >= DATE '<DT_FROM>'
    AND ds.dt_snapshot <= DATE '<DT_TO>'
    AND ds.year >= YEAR(DATE '<DT_FROM>')
    AND ds.year <= YEAR(DATE '<DT_TO>')
ORDER BY ds.dt_snapshot, ds.id_dag
LIMIT 5000
```

### YAML producers (do this before the SQL below)

For each missed `id_dag`, open that key in `dags/dependencies.yaml`. Producer = substring before the first `:`. Exact name only. Empty / missing key → no chain → do not guess upstreams; cause stays **Indeterminada** until proven otherwise.

### Upstream SLA for a producer list on one snapshot day

IN-list = **only** YAML producers of that consumer. Same `dt_snapshot` as the consumer miss. Do not add other-team DAGs that happened to miss the same day.

**Do not filter `is_outside_sla = TRUE`.** This table can emit two rows per DAG×day (one inside with `ts_ok`, one outside with null timestamp). Fetch all rows and collapse in the agent: a producer missed only if **no** row is `is_inside_sla` with a non-null success timestamp before the consumer layer SLA.

```sql
SELECT
    CAST(ds.dt_snapshot AS varchar) AS dt_snapshot,
    ds.id_dag,
    d.line_name,
    d.id_line,
    ds.is_inside_sla,
    ds.is_outside_sla,
    ds.is_run_failed,
    ds.is_run_successful,
    CAST(ds.ts_first_execution_success_brt AS varchar) AS ts_first_execution_success_brt
FROM hive.datalake_pipeline.dag_sla_information AS ds
INNER JOIN hive.datalake_pipeline.dag AS d
    ON d.id_dag = ds.id_dag
WHERE ds.dt_snapshot = DATE '<SNAPSHOT>'
    AND ds.year = YEAR(DATE '<SNAPSHOT>')
    AND ds.month = MONTH(DATE '<SNAPSHOT>')
    AND ds.day = DAY(DATE '<SNAPSHOT>')
    AND ds.id_dag IN ('bietlejuice.producer_a', 'bietlejuice.producer_b')
LIMIT 500
```

`quintoml.*` producers are not in `datalake_pipeline.dag`. Treat a miss as **cascata externa** (MLOps) when the consumer waited on them; do not require a pipeline SLA row.

---

## Data quality

### Freshness gate (run first)

`enrich_data_quality` only republishes Inmetro. Check **both** tables. A green Airflow run that writes zero rows is an empty incremental window, not a failed DAG and not “zero alerts”.

```sql
SELECT
    'enrich' AS src,
    CAST(MAX(dt_executed) AS varchar) AS max_dt,
    COUNT(*) AS qt
FROM hive.datalake_data_quality.validations
WHERE year >= YEAR(DATE '<DT_FROM>') - 1
    AND year <= YEAR(DATE '<DT_TO>')
UNION ALL
SELECT
    'inmetro_clean' AS src,
    CAST(MAX(DATE(ts_execution_local)) AS varchar) AS max_dt,
    COUNT(*) AS qt
FROM hive.datalake_inmetro_clean.data_validations
WHERE year >= YEAR(DATE '<DT_FROM>') - 1
    AND year <= YEAR(DATE '<DT_TO>')
    AND repo = 'bietlejuice'
LIMIT 5
```

If **both** `max_dt` values are older than `<DT_FROM>`, the origin stopped: there is no partition in the ritual window on either table. Name that last day on the canvas and skip the alert list. Do not say the DAG is down.

If enrich is older than `<DT_FROM>` but Inmetro is inside the window, use the fallback join below.

### Open failures (latest row per check still failing)

```sql
WITH team_dags AS (
    SELECT id_dag
    FROM hive.datalake_pipeline.dag
    WHERE line_name = '<LINE_NAME>'
        AND is_active = TRUE
),
bounded AS (
    SELECT
        v.id_dag,
        v.database,
        v."table" AS table_name,
        v.column,
        v.validation_type,
        v.validation_status,
        v.table_status,
        v.consecutive_failure_days,
        CAST(v.dt_executed AS varchar) AS dt_executed
    FROM hive.datalake_data_quality.validations AS v
    INNER JOIN team_dags AS td
        ON td.id_dag = v.id_dag
    WHERE v.dt_executed >= DATE '<DT_FROM>'
        AND v.dt_executed <= DATE '<DT_TO>'
        AND v.year >= YEAR(DATE '<DT_FROM>')
        AND v.year <= YEAR(DATE '<DT_TO>')
),
ranked AS (
    SELECT
        bounded.id_dag,
        bounded.database,
        bounded.table_name,
        bounded.column,
        bounded.validation_type,
        bounded.validation_status,
        bounded.table_status,
        bounded.consecutive_failure_days,
        bounded.dt_executed,
        ROW_NUMBER() OVER (
            PARTITION BY
                bounded.id_dag,
                bounded.database,
                bounded.table_name,
                bounded.column,
                bounded.validation_type
            ORDER BY bounded.dt_executed DESC
        ) AS rn
    FROM bounded
)
SELECT
    id_dag,
    database,
    table_name,
    column,
    validation_type,
    validation_status,
    table_status,
    consecutive_failure_days,
    dt_executed
FROM ranked
WHERE rn = 1
    AND (
        validation_status = 'failure'
        OR table_status IN ('error', 'warning')
    )
ORDER BY consecutive_failure_days DESC, id_dag, table_name
LIMIT 2000
```

### 15-day volume

```sql
SELECT
    v.id_dag,
    v.database,
    v."table" AS table_name,
    v.validation_type,
    v.table_status,
    COUNT(*) AS qt_fail_rows,
    CAST(MIN(v.dt_executed) AS varchar) AS dt_first_fail,
    CAST(MAX(v.dt_executed) AS varchar) AS dt_last_fail,
    MAX(v.consecutive_failure_days) AS max_consecutive_failure_days
FROM hive.datalake_data_quality.validations AS v
INNER JOIN hive.datalake_pipeline.dag AS d
    ON d.id_dag = v.id_dag
WHERE d.line_name = '<LINE_NAME>'
    AND v.dt_executed >= DATE '<DT_FROM>'
    AND v.dt_executed <= DATE '<DT_TO>'
    AND v.year >= YEAR(DATE '<DT_FROM>')
    AND v.year <= YEAR(DATE '<DT_TO>')
    AND (
        v.validation_status = 'failure'
        OR v.table_status IN ('error', 'warning')
    )
GROUP BY
    v.id_dag,
    v.database,
    v."table",
    v.validation_type,
    v.table_status
ORDER BY max_consecutive_failure_days DESC, qt_fail_rows DESC
LIMIT 2000
```

---

## DEI (Jira)

Authenticate Atlassian MCP first. `cloudId`: `8a4667b7-87a1-4c6c-805c-fc0d6e60a7a0`.

Preferred JQL (Incident Owner). Use the **DEI label** from [aliases.md](aliases.md). Expect **0 rows** when the field is empty (common — the UI name is `Incident Owner [DEPRECATED]`).

```
project = DEI AND status IN ("To Do", "In Progress") AND "Incident Owner[Dropdown]" = "Data Growth" ORDER BY created DESC
```

Fallback if the field clause errors:

```
project = DEI AND status IN ("To Do", "In Progress") AND cf[12078] = 55173 ORDER BY created DESC
```

(IDs in `fill-incident-card`. `55173` is Data Growth.)

**Always also run** (then filter in the agent by team `id_dag` in `summary`):

```
project = DEI AND status IN ("To Do", "In Progress") ORDER BY created DESC
```

Request `view: evidence` and fields: `summary`, `status`, `assignee`, `created`, `customfield_12078`, `customfield_11195`, `customfield_12350`, `customfield_30056`.

---

## Grafana / Prometheus

Observability MCP `query_metrics`: `source=thanos`, `cluster=data-prd` (fallback `shared-prd`). Instant query; the window is inside PromQL.

Same PromQL for EMR and leftover Databricks. Label is `cluster_name` = bare DAG name. EMR dashboard variable is `dag_name`.

- EMR (most DAGs): UID `een6dh4u4aqdcd` — [Spark clusters DAGs overview](https://grafana.apps.shared-prd.habitat.zone/d/een6dh4u4aqdcd/spark-clusters-dags-overview?orgId=1&from=now-24h&to=now&timezone=browser&var-env=prod&var-project=bietlejuice&var-dag_name=)
- Databricks (remaining): UID `2_zM2pZ4z` — [Databricks clusters comparison](https://grafana.apps.shared-prd.habitat.zone/d/2_zM2pZ4z/databricks-clusters-comparison-between-dags?orgId=1&from=now-24h&to=now&timezone=browser&var-env=prod&var-project=bietlejuice)

Filter series client-side on **bare DAG name** (`gsheets_growth`, not `bietlejuice.gsheets_growth`).

Spill (bytes; flag `> 0`):

```promql
sort_desc(
  sum by (cluster_name) (
    max by (cluster_name, component) (
      max_over_time(databricks_executor{project="bietlejuice",type="diskBytesSpilled"}[15d])
    )
  ) > 0
)
```

Swap (flag `> 0`):

```promql
sort_desc(
  max_over_time(
    sum by (cluster_name) (
      databricks_plugin_cgroup_metrics{project="bietlejuice",type="MemorySwap"}
    )[15d:]
  ) > 0
)
```

Total memory ratio (flag `≥ 0.80`):

```promql
sort_desc(
  max_over_time(
    (
      sum by (cluster_name) (databricks_plugin_ganglia_metrics{project="bietlejuice",type="UsedMemory"})
      /
      sum by (cluster_name) (databricks_plugin_ganglia_metrics{project="bietlejuice",type="TotalMemory"})
    )[15d:]
  )
)
```

Relative CPU (flag `≥ 0.80`):

```promql
sort_desc(
  max by (cluster_name) (
    max_over_time(
      (1 - databricks_plugin_ganglia_metrics{project="bietlejuice",type="IdleCPU"})[15d:]
    )
  )
)
```

Optional 24h cut (matches the Grafana default range) — same queries with `[1d]` / `[1d:]` instead of `[15d]`. Report 15d as the ritual window; mention 24h only if it changes who is on fire *today*.
