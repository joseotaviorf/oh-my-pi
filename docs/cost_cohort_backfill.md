# cost_cohort Backfill Runbook (Phase C audit copy)

Audit copy of the one-time prod operations that added the `cost_cohort` column to the Databricks cost & health lineage and enriched all of 2026 history in place. Run on the QuintoAndar Databricks workspace (SQL editor or `databricks` CLI); `data-platform-engineers` has ALL PRIVILEGES on every target table.

## Why in-place MERGE instead of re-running the DAGs

History must NOT be recomputed by re-running the DAGs. `system.compute.node_timeline` has rolling retention; re-running Jan–May today would re-price historical EC2 against a shifted retention window (days that had node-timeline coverage on the original 2026-06-06/07 backfill would silently fall back to `billable_usage_estimate`/`missing`). Historical rows get the new column via in-place `MERGE` computed ONLY from columns already materialized in each fact plus the seed dim `datalake_databricks_pricing.dim_cost_cohort` — deterministic, and it cannot change any metric. This phase touches ONLY the new column: DBU/EC2/hours/flags are read, never written, so the pre-verified 2026 monthly row-count and `total_cost_usd` anchors must hold exactly after the MERGE.

## Cutoff rule

Set `<CUTOFF>` = (prod deploy date − 3 days) so the MERGE never touches days the daily D-2..D window will rewrite.

## Execution order

1. **DDL** — immediately after the prod deploy, BEFORE the next 09:00 UTC scheduled runs, so the new query code never races a missing column. Skip any statement whose column already exists (check with `DESCRIBE TABLE <t>` first). The two `metric_observability` ALTERs land after PR4 merges.
2. **Trigger `enrich_databricks_pricing`** (manual, prod) → materializes `dim_cost_cohort`.
3. **Let one scheduled 09:00 UTC run of each fact complete** (writes new days with the column populated by the new code).
4. **History MERGE** — the three statements below.
5. **No metric-layer MERGE** — `metric_observability.dag_health` / `dag_health_wow` are rolling 7d/28d snapshots and fill forward from daily runs; the ALTERs pre-create the column so the first post-deploy run cannot fail on schema. Historical cohort trends come from `fact_databricks_dag_run`.

## DDL

```sql
ALTER TABLE dw_databricks_costs.fact_databricks_costs      ADD COLUMNS (cost_cohort STRING AFTER provisioner_resolved);
ALTER TABLE dw_databricks_health.fact_databricks_task_run  ADD COLUMNS (cost_cohort STRING AFTER provisioner);
ALTER TABLE dw_databricks_health.fact_databricks_dag_run   ADD COLUMNS (cost_cohort STRING AFTER provisioner);
ALTER TABLE metric_observability.dag_health                ADD COLUMNS (cost_cohort STRING AFTER provisioner);
ALTER TABLE metric_observability.dag_health_wow            ADD COLUMNS (cost_cohort STRING AFTER provisioner);
```

If `AFTER` is rejected, drop the clause (column appends last physically; logical order in metadata/queries is unaffected).

## History MERGE — spine (`fact_databricks_costs`)

```sql
MERGE INTO dw_databricks_costs.fact_databricks_costs AS f
USING (
    SELECT
        s.sk_databricks_cost,
        s.dt_usage,
        COALESCE(MIN_BY(r.cost_cohort, r.priority), 'other') AS cost_cohort
    FROM (
        SELECT
            sk_databricks_cost, dt_usage, team_owner, provisioner_resolved,
            regexp_replace(regexp_replace(
                CASE WHEN COALESCE(workload_name, '') RLIKE '(_scheduled__|_manual__|_dataset__|_dataset_triggered__|__)'
                     THEN regexp_extract(regexp_replace(COALESCE(workload_name, ''), '^job-[0-9]+-run-[0-9]+-', ''),
                                         '^(.*?)(_scheduled__|_manual__|_dataset__|_dataset_triggered__|__).*', 1)
                     ELSE COALESCE(workload_name, '') END,
                '^bietlejuice-', 'bietlejuice.'), '^quintoml-wonka-', 'quintoml.wonka.') AS wn
        FROM dw_databricks_costs.fact_databricks_costs
        WHERE dt_usage BETWEEN DATE('2026-01-01') AND DATE('<CUTOFF>')
    ) s
    LEFT JOIN datalake_databricks_pricing.dim_cost_cohort r
        ON (r.rule_type = 'team_owner_exact'  AND s.team_owner = r.match_value)
        OR (r.rule_type = 'team_owner_prefix' AND s.team_owner LIKE CONCAT(r.match_value, '%'))
        OR (r.rule_type = 'provisioner_exact' AND s.provisioner_resolved = r.match_value)
        OR (r.rule_type = 'workload_prefix'   AND LOWER(s.wn) LIKE CONCAT(r.match_value, '%'))
        OR (r.rule_type = 'workload_like'     AND LOWER(s.wn) LIKE r.match_value)
    GROUP BY s.sk_databricks_cost, s.dt_usage
) AS m
ON  f.sk_databricks_cost = m.sk_databricks_cost
AND f.dt_usage = m.dt_usage
AND f.dt_usage BETWEEN DATE('2026-01-01') AND DATE('<CUTOFF>')
WHEN MATCHED THEN UPDATE SET f.cost_cohort = m.cost_cohort;
```

## History MERGE — `fact_databricks_task_run`

Identical shape to the spine, keyed on `sk_databricks_task_run` + `dt_task_started`, source columns `team_owner, provisioner, airflow_dag_id`. No `wn` normalization — `airflow_dag_id` is already canonical (full framework prefixes); `LOWER(airflow_dag_id)` feeds the two workload predicates.

```sql
MERGE INTO dw_databricks_health.fact_databricks_task_run AS f
USING (
    SELECT
        s.sk_databricks_task_run,
        s.dt_task_started,
        COALESCE(MIN_BY(r.cost_cohort, r.priority), 'other') AS cost_cohort
    FROM (
        SELECT
            sk_databricks_task_run, dt_task_started, team_owner, provisioner, airflow_dag_id
        FROM dw_databricks_health.fact_databricks_task_run
        WHERE dt_task_started BETWEEN DATE('2026-01-01') AND DATE('<CUTOFF>')
    ) s
    LEFT JOIN datalake_databricks_pricing.dim_cost_cohort r
        ON (r.rule_type = 'team_owner_exact'  AND s.team_owner = r.match_value)
        OR (r.rule_type = 'team_owner_prefix' AND s.team_owner LIKE CONCAT(r.match_value, '%'))
        OR (r.rule_type = 'provisioner_exact' AND s.provisioner = r.match_value)
        OR (r.rule_type = 'workload_prefix'   AND LOWER(s.airflow_dag_id) LIKE CONCAT(r.match_value, '%'))
        OR (r.rule_type = 'workload_like'     AND LOWER(s.airflow_dag_id) LIKE r.match_value)
    GROUP BY s.sk_databricks_task_run, s.dt_task_started
) AS m
ON  f.sk_databricks_task_run = m.sk_databricks_task_run
AND f.dt_task_started = m.dt_task_started
AND f.dt_task_started BETWEEN DATE('2026-01-01') AND DATE('<CUTOFF>')
WHEN MATCHED THEN UPDATE SET f.cost_cohort = m.cost_cohort;
```

## History MERGE — `fact_databricks_dag_run`

Identical shape, keyed on `sk_databricks_dag_run` + `dt_dag_run_started`, same three source columns as task_run. The cohort is re-derived from dag_run's own columns rather than propagated from task_run — equivalent by determinism: cohort is a pure function of (dag id, tags), which dag_run carries.

```sql
MERGE INTO dw_databricks_health.fact_databricks_dag_run AS f
USING (
    SELECT
        s.sk_databricks_dag_run,
        s.dt_dag_run_started,
        COALESCE(MIN_BY(r.cost_cohort, r.priority), 'other') AS cost_cohort
    FROM (
        SELECT
            sk_databricks_dag_run, dt_dag_run_started, team_owner, provisioner, airflow_dag_id
        FROM dw_databricks_health.fact_databricks_dag_run
        WHERE dt_dag_run_started BETWEEN DATE('2026-01-01') AND DATE('<CUTOFF>')
    ) s
    LEFT JOIN datalake_databricks_pricing.dim_cost_cohort r
        ON (r.rule_type = 'team_owner_exact'  AND s.team_owner = r.match_value)
        OR (r.rule_type = 'team_owner_prefix' AND s.team_owner LIKE CONCAT(r.match_value, '%'))
        OR (r.rule_type = 'provisioner_exact' AND s.provisioner = r.match_value)
        OR (r.rule_type = 'workload_prefix'   AND LOWER(s.airflow_dag_id) LIKE CONCAT(r.match_value, '%'))
        OR (r.rule_type = 'workload_like'     AND LOWER(s.airflow_dag_id) LIKE r.match_value)
    GROUP BY s.sk_databricks_dag_run, s.dt_dag_run_started
) AS m
ON  f.sk_databricks_dag_run = m.sk_databricks_dag_run
AND f.dt_dag_run_started = m.dt_dag_run_started
AND f.dt_dag_run_started BETWEEN DATE('2026-01-01') AND DATE('<CUTOFF>')
WHEN MATCHED THEN UPDATE SET f.cost_cohort = m.cost_cohort;
```

## Post-MERGE verification

After the MERGE, the 2026 monthly anchors (row counts and `SUM(total_cost_usd)`) for months 1–5 must match the pre-change values exactly (frozen partitions); month 6 within ±0.5% (late billing corrections restated by daily runs are legitimate). Any row-count drift in months 1–5 = fan-out or MERGE bug — stop and investigate. The health-family zero-`other` data-quality check (Error) must return 0 rows for all of 2026.
