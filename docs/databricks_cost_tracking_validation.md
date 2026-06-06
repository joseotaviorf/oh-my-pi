# Databricks Cost Tracking Validation

This document provides read-only Databricks SQL checks for the Databricks cost and health tracking lineage. The goal is Platform cost-reduction tracking and operational right-sizing, not finance-grade invoice reproduction.

Use `dw_databricks_costs.fact_databricks_costs` as the total Platform Databricks cost authority. Use `metric_observability.dag_health` and `metric_observability.dag_health_wow` for per-DAG trend and right-sizing analysis.

## Expected Thresholds

- Stable-date DBU reconciliation: error above 1 DBU per workspace, day, and billing product.
- Fresh-date DBU reconciliation: warning only for the freshest two fact dates.
- `price_missing` share: warning above 5 percent YTD DBU.
- Before retained `node_timeline` coverage: `billable_usage_estimate` is expected for QA and Prod workspaces where legacy `billable_usage` has machine hours.
- Before retained `node_timeline` coverage in Forno: expected to remain `missing` unless a future coarse estimator is explicitly approved.
- On or after the first retained `node_timeline` day per workspace: cluster-backed rows should use `node_timeline`, except for system-table freshness lag.
- Metric windows before retained `node_timeline` coverage may include estimated EC2. Dashboards should surface `has_ec2_estimate_*` flags before comparing estimated vs timeline-backed EC2.

## Stable DBU Reconciliation

```sql
WITH fact_dbu AS (
    SELECT
        id_databricks_workspace AS workspace_id,
        dt_usage,
        billing_origin_product,
        SUM(dbu) AS fact_dbu
    FROM dw_databricks_costs.fact_databricks_costs
    WHERE dt_usage BETWEEN DATE('2026-01-01') AND DATE_SUB(CURRENT_DATE(), 2)
    GROUP BY
        id_databricks_workspace,
        dt_usage,
        billing_origin_product
),
billing_dbu AS (
    SELECT
        workspace_id,
        DATE(usage_date) AS dt_usage,
        billing_origin_product,
        SUM(usage_quantity) AS bill_dbu
    FROM system.billing.usage
    WHERE usage_unit = 'DBU'
      AND workspace_id IN (4531937035440038, 6170817193817, 4033397625841925)
      AND DATE(usage_date) BETWEEN DATE('2026-01-01') AND DATE_SUB(CURRENT_DATE(), 2)
    GROUP BY
        workspace_id,
        DATE(usage_date),
        billing_origin_product
    HAVING SUM(usage_quantity) <> 0
)
SELECT
    COALESCE(f.workspace_id, b.workspace_id) AS workspace_id,
    COALESCE(f.dt_usage, b.dt_usage) AS dt_usage,
    COALESCE(f.billing_origin_product, b.billing_origin_product) AS billing_origin_product,
    COALESCE(f.fact_dbu, 0) AS fact_dbu,
    COALESCE(b.bill_dbu, 0) AS bill_dbu,
    COALESCE(f.fact_dbu, 0) - COALESCE(b.bill_dbu, 0) AS dbu_delta
FROM fact_dbu f
FULL OUTER JOIN billing_dbu b
    ON f.workspace_id = b.workspace_id
   AND f.dt_usage = b.dt_usage
   AND f.billing_origin_product = b.billing_origin_product
WHERE ABS(COALESCE(f.fact_dbu, 0) - COALESCE(b.bill_dbu, 0)) > 1.0
ORDER BY ABS(COALESCE(f.fact_dbu, 0) - COALESCE(b.bill_dbu, 0)) DESC;
```

Expected result: zero rows for settled dates.

## Fresh-Day DBU Drift

```sql
WITH max_fact_date AS (
    SELECT MAX(dt_usage) AS max_dt_usage
    FROM dw_databricks_costs.fact_databricks_costs
)
SELECT
    f.id_databricks_workspace AS workspace_id,
    f.dt_usage,
    f.billing_origin_product,
    SUM(f.dbu) AS fact_dbu,
    SUM(b.usage_quantity) AS bill_dbu,
    SUM(f.dbu) - SUM(b.usage_quantity) AS dbu_delta
FROM dw_databricks_costs.fact_databricks_costs f
LEFT JOIN system.billing.usage b
    ON b.workspace_id = f.id_databricks_workspace
   AND DATE(b.usage_date) = f.dt_usage
   AND b.billing_origin_product = f.billing_origin_product
   AND b.usage_unit = 'DBU'
CROSS JOIN max_fact_date m
WHERE f.dt_usage > DATE_SUB(m.max_dt_usage, 2)
GROUP BY
    f.id_databricks_workspace,
    f.dt_usage,
    f.billing_origin_product
HAVING ABS(SUM(f.dbu) - COALESCE(SUM(b.usage_quantity), 0)) > 1.0
ORDER BY f.dt_usage DESC, ABS(SUM(f.dbu) - COALESCE(SUM(b.usage_quantity), 0)) DESC;
```

Expected result: warning-only rows are acceptable for the latest two fact dates.

## EC2 Source Coverage

```sql
SELECT
    dt_usage,
    id_databricks_workspace,
    ec2_source,
    is_ec2_estimated,
    COUNT(*) AS rows,
    ROUND(SUM(ec2_cost_usd), 2) AS ec2_cost_usd,
    ROUND(SUM(on_demand_hours), 2) AS on_demand_hours,
    ROUND(SUM(spot_hours), 2) AS spot_hours,
    ROUND(SUM(ec2_unpriced_hours), 2) AS ec2_unpriced_hours
FROM dw_databricks_costs.fact_databricks_costs
WHERE dt_usage >= DATE('2026-01-01')
GROUP BY
    dt_usage,
    id_databricks_workspace,
    ec2_source,
    is_ec2_estimated
ORDER BY dt_usage, id_databricks_workspace, ec2_source;
```

Expected result: before the first retained `node_timeline` day for each workspace, QA and Prod can show `billable_usage_estimate`; Forno can show `missing`. On and after that coverage start, cluster-backed EC2 should mostly be `node_timeline`.

## Pre-Node-Timeline Estimated EC2 Hours

```sql
WITH node_timeline_coverage AS (
    SELECT
        CAST(workspace_id AS BIGINT) AS id_databricks_workspace,
        MIN(DATE(start_time)) AS dt_node_timeline_first_available
    FROM system.compute.node_timeline
    WHERE workspace_id IN (4531937035440038, 6170817193817)
    GROUP BY CAST(workspace_id AS BIGINT)
)
SELECT
    fact.id_databricks_workspace,
    fact.ec2_source,
    ROUND(SUM(fact.on_demand_hours + fact.spot_hours), 2) AS ec2_hours,
    ROUND(SUM(fact.ec2_cost_usd), 2) AS ec2_cost_usd
FROM dw_databricks_costs.fact_databricks_costs fact
LEFT JOIN node_timeline_coverage coverage
    ON fact.id_databricks_workspace = coverage.id_databricks_workspace
WHERE fact.dt_usage >= DATE('2026-01-01')
  AND fact.dt_usage < COALESCE(coverage.dt_node_timeline_first_available, CURRENT_DATE())
GROUP BY
    fact.id_databricks_workspace,
    fact.ec2_source
ORDER BY fact.id_databricks_workspace, fact.ec2_source;
```

Expected result: `billable_usage_estimate` appears where legacy machine hours exist before retained `node_timeline` coverage. Forno is expected to have no estimate.

## DBU List Fallback Share

```sql
SELECT
    pricing_category,
    billing_origin_product,
    ROUND(SUM(dbu), 2) AS dbu,
    ROUND(SUM(dbu_cost_usd), 2) AS dbu_cost_usd,
    ROUND(
        SUM(CASE WHEN price_missing THEN dbu ELSE 0 END)
        / NULLIF(SUM(dbu), 0),
        4
    ) AS price_missing_dbu_share
FROM dw_databricks_costs.fact_databricks_costs
WHERE dt_usage >= DATE('2026-01-01')
GROUP BY
    pricing_category,
    billing_origin_product
ORDER BY price_missing_dbu_share DESC, dbu DESC;
```

Expected result: total `price_missing` share should remain below 5 percent YTD DBU unless Platform accepts a higher list-fallback share.

## EC2 Missing Price Checks

```sql
SELECT
    dt_usage,
    id_databricks_workspace,
    ec2_source,
    COUNT(*) AS rows_with_missing_price,
    ROUND(SUM(ec2_unpriced_hours), 2) AS ec2_unpriced_hours
FROM dw_databricks_costs.fact_databricks_costs
WHERE ec2_pricing_missing = TRUE
GROUP BY
    dt_usage,
    id_databricks_workspace,
    ec2_source
ORDER BY dt_usage DESC, ec2_unpriced_hours DESC;
```

Expected result: no `node_timeline` rows with missing prices after retained `node_timeline` coverage begins.

## Health-Family EC2 Coverage

```sql
SELECT
    'daily_cluster_health' AS table_name,
    dt_cluster_run AS dt_reference,
    id_databricks_workspace,
    ec2_source,
    is_ec2_estimated,
    COUNT(*) AS rows,
    ROUND(SUM(total_ec2_cost_calculated_usd), 2) AS ec2_cost_usd
FROM datalake_databricks_health.daily_cluster_health
WHERE dt_cluster_run >= DATE('2026-01-01')
GROUP BY dt_cluster_run, id_databricks_workspace, ec2_source, is_ec2_estimated

UNION ALL

SELECT
    'fact_databricks_task_run' AS table_name,
    dt_task_started AS dt_reference,
    id_databricks_workspace,
    ec2_source,
    is_ec2_estimated,
    COUNT(*) AS rows,
    ROUND(SUM(total_ec2_cost_calculated_usd), 2) AS ec2_cost_usd
FROM dw_databricks_health.fact_databricks_task_run
WHERE dt_task_started >= DATE('2026-01-01')
GROUP BY dt_task_started, id_databricks_workspace, ec2_source, is_ec2_estimated

UNION ALL

SELECT
    'fact_databricks_dag_run' AS table_name,
    dt_dag_run_started AS dt_reference,
    id_databricks_workspace,
    ec2_source,
    is_ec2_estimated,
    COUNT(*) AS rows,
    ROUND(SUM(total_ec2_cost_calculated_usd), 2) AS ec2_cost_usd
FROM dw_databricks_health.fact_databricks_dag_run
WHERE dt_dag_run_started >= DATE('2026-01-01')
GROUP BY dt_dag_run_started, id_databricks_workspace, ec2_source, is_ec2_estimated
ORDER BY table_name, dt_reference, id_databricks_workspace, ec2_source;
```

Expected result: the health family should show `billable_usage_estimate` before retained `node_timeline` coverage after backfill, and `node_timeline` from the first retained coverage day onward.

## Task EC2 vs Daily Cluster EC2

```sql
WITH cluster_health AS (
    SELECT
        id_databricks_workspace,
        dt_cluster_run,
        ROUND(SUM(total_ec2_cost_calculated_usd), 2) AS daily_cluster_ec2_usd
    FROM datalake_databricks_health.daily_cluster_health
    WHERE dt_cluster_run >= DATE('2026-01-01')
    GROUP BY id_databricks_workspace, dt_cluster_run
),
task_fact AS (
    SELECT
        id_databricks_workspace,
        dt_task_started AS dt_cluster_run,
        ROUND(SUM(total_ec2_cost_calculated_usd), 2) AS task_attributed_ec2_usd
    FROM dw_databricks_health.fact_databricks_task_run
    WHERE dt_task_started >= DATE('2026-01-01')
    GROUP BY id_databricks_workspace, dt_task_started
)
SELECT
    COALESCE(ch.id_databricks_workspace, tf.id_databricks_workspace) AS id_databricks_workspace,
    COALESCE(ch.dt_cluster_run, tf.dt_cluster_run) AS dt_cluster_run,
    ch.daily_cluster_ec2_usd,
    tf.task_attributed_ec2_usd,
    ch.daily_cluster_ec2_usd - COALESCE(tf.task_attributed_ec2_usd, 0) AS not_task_attributed_ec2_usd
FROM cluster_health ch
FULL OUTER JOIN task_fact tf
    ON ch.id_databricks_workspace = tf.id_databricks_workspace
   AND ch.dt_cluster_run = tf.dt_cluster_run
ORDER BY dt_cluster_run, id_databricks_workspace;
```

Expected result: task-attributed EC2 can be lower than daily cluster EC2 because interactive notebooks, ad-hoc jobs, non-Lakeflow workloads, and idle time are not attributed to Lakeflow tasks.

## Orchestrated Slice Cross-Check

```sql
WITH cost_fact AS (
    SELECT
        dt_usage,
        id_databricks_workspace,
        ROUND(SUM(dbu_cost_usd + ec2_cost_usd), 2) AS cost_fact_orchestrated_usd
    FROM dw_databricks_costs.fact_databricks_costs
    WHERE dt_usage >= DATE('2026-01-01')
      AND bucket = 'orchestrated_jobs'
    GROUP BY dt_usage, id_databricks_workspace
),
task_fact AS (
    SELECT
        dt_task_started AS dt_usage,
        id_databricks_workspace,
        ROUND(SUM(total_cost_usd), 2) AS task_fact_orchestrated_usd
    FROM dw_databricks_health.fact_databricks_task_run
    WHERE dt_task_started >= DATE('2026-01-01')
      AND NOT is_job_on_interactive
    GROUP BY dt_task_started, id_databricks_workspace
)
SELECT
    COALESCE(cf.dt_usage, tf.dt_usage) AS dt_usage,
    COALESCE(cf.id_databricks_workspace, tf.id_databricks_workspace) AS id_databricks_workspace,
    cf.cost_fact_orchestrated_usd,
    tf.task_fact_orchestrated_usd,
    cf.cost_fact_orchestrated_usd - tf.task_fact_orchestrated_usd AS usd_delta
FROM cost_fact cf
FULL OUTER JOIN task_fact tf
    ON cf.dt_usage = tf.dt_usage
   AND cf.id_databricks_workspace = tf.id_databricks_workspace
ORDER BY dt_usage, id_databricks_workspace;
```

Expected result: this is a directional sanity check only. `fact_databricks_costs` remains the cost authority; task facts remain operational attribution.

## Consumer Guidance

- Total Platform Databricks tracking: `dw_databricks_costs.fact_databricks_costs`.
- Per-DAG right-sizing and trend analysis: `metric_observability.dag_health`.
- Week-over-week per-DAG movement: `metric_observability.dag_health_wow`.
- Legacy `dw_analytical_costs` and `usage_costs`: historical comparisons only, not 2026 cost-reduction tracking.
- EC2 before retained `node_timeline` coverage should be visually separated from timeline-backed EC2 because source quality changes from estimated machine hours to node timeline.
