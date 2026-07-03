-- Audit copy of Superset virtual dataset 21993 ("dag_health_node_hours_by_instance", dashboard 3969 /
-- TARS: DAG Health - Costs).
-- Deployed 2026-07-03 via PUT /api/v1/dataset/21993 (cost_cohort rollout).
-- Threaded airflow_dag_id + cost_cohort through the proration CTE chain
-- (runs -> expanded -> overlaps -> allocated -> slots) as pass-through dimensions.
-- Any future edit to the live dataset MUST update this file in the same
-- change — untracked dataset edits caused the June-17 cost report incident.

-- Virtual dataset: dag_health_node_hours_by_instance
-- Prorated total cost (USD) and node-hours by instance family and size per day bucket.
-- Dashboard native filters apply to output columns (no Jinja).

WITH runs AS (
    SELECT
        sk_databricks_dag_run,
        ts_run_started_min,
        COALESCE(
            ts_run_ended_max,
            ts_run_started_min + INTERVAL '1' SECOND
        ) AS ts_run_ended,
        COALESCE(ec2_on_demand_hours, 0) + COALESCE(ec2_spot_hours, 0) AS total_node_hours,
        COALESCE(total_cost_usd, 0) AS total_cost_usd,
        COALESCE(
            worker_count,
            peak_concurrent_workers,
            primary_max_autoscale_workers,
            0
        ) AS n_workers,
        driver_node_type,
        COALESCE(worker_node_type, driver_node_type) AS worker_node_type,
        dt_dag_run_started,
        provisioner,
        id_databricks_workspace,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        CASE
            WHEN REGEXP_LIKE(airflow_dag_id, '__validation$') THEN 'Validation DAG'
            ELSE 'Standard DAG'
        END AS dag_run_type
    FROM
        delta.dw_databricks_health.fact_databricks_dag_run
    WHERE
        dt_dag_run_started >= DATE '2026-01-01'
        AND (COALESCE(ec2_on_demand_hours, 0) + COALESCE(ec2_spot_hours, 0)) > 0
),
run_wall AS (
    SELECT
        *,
        GREATEST(
            DATE_DIFF('second', ts_run_started_min, ts_run_ended),
            1
        ) AS run_wall_seconds
    FROM
        runs
),
expanded AS (
    SELECT
        r.sk_databricks_dag_run,
        r.ts_run_started_min,
        r.ts_run_ended,
        r.total_node_hours,
        r.total_cost_usd,
        r.n_workers,
        r.driver_node_type,
        r.worker_node_type,
        r.run_wall_seconds,
        r.dt_dag_run_started,
        r.provisioner,
        r.id_databricks_workspace,
        r.team_owner,
        r.airflow_dag_id,
        r.cost_cohort,
        r.dag_run_type,
        t.bucket_idx,
        DATE_TRUNC('day', r.ts_run_started_min)
            + t.bucket_idx * INTERVAL '1' DAY AS bucket_start,
        DATE_TRUNC('day', r.ts_run_started_min)
            + (t.bucket_idx + 1) * INTERVAL '1' DAY AS bucket_end
    FROM
        run_wall AS r
        CROSS JOIN UNNEST(
            SEQUENCE(
                0,
                DATE_DIFF(
                    'day',
                    DATE_TRUNC('day', r.ts_run_started_min),
                    DATE_TRUNC('day', r.ts_run_ended)
                )
            )
        ) AS t(bucket_idx)
),
overlaps AS (
    SELECT
        e.bucket_start AS dt_period,
        e.driver_node_type,
        e.worker_node_type,
        e.n_workers,
        e.total_node_hours,
        e.total_cost_usd,
        e.run_wall_seconds,
        e.dt_dag_run_started,
        e.provisioner,
        e.id_databricks_workspace,
        e.team_owner,
        e.airflow_dag_id,
        e.cost_cohort,
        e.dag_run_type,
        GREATEST(
            0,
            DATE_DIFF(
                'second',
                GREATEST(e.ts_run_started_min, e.bucket_start),
                LEAST(e.ts_run_ended, e.bucket_end)
            )
        ) AS overlap_seconds
    FROM
        expanded AS e
),
allocated AS (
    SELECT
        dt_period,
        driver_node_type,
        worker_node_type,
        n_workers,
        dt_dag_run_started,
        provisioner,
        id_databricks_workspace,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type,
        total_node_hours * overlap_seconds / CAST(run_wall_seconds AS DOUBLE) AS allocated_node_hours,
        total_cost_usd * overlap_seconds / CAST(run_wall_seconds AS DOUBLE) AS allocated_total_cost_usd
    FROM
        overlaps
    WHERE
        overlap_seconds > 0
),
slots AS (
    SELECT
        dt_period,
        driver_node_type AS node_type,
        allocated_node_hours * 1.0 / (1.0 + CAST(n_workers AS DOUBLE)) AS node_hours,
        allocated_total_cost_usd * 1.0 / (1.0 + CAST(n_workers AS DOUBLE)) AS total_cost_usd,
        dt_dag_run_started,
        provisioner,
        id_databricks_workspace,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type
    FROM
        allocated
    UNION ALL
    SELECT
        dt_period,
        worker_node_type AS node_type,
        allocated_node_hours * CAST(n_workers AS DOUBLE) / (1.0 + CAST(n_workers AS DOUBLE)) AS node_hours,
        allocated_total_cost_usd * CAST(n_workers AS DOUBLE) / (1.0 + CAST(n_workers AS DOUBLE)) AS total_cost_usd,
        dt_dag_run_started,
        provisioner,
        id_databricks_workspace,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type
    FROM
        allocated
    WHERE
        n_workers > 0
)
SELECT
    dt_period,
    REGEXP_EXTRACT(node_type, '^([a-z0-9]+)[.-]', 1) AS instance_family,
    REGEXP_EXTRACT(node_type, '\.([a-z0-9]+)$', 1) AS instance_size,
    ROUND(SUM(total_cost_usd), 4) AS total_cost_usd,
    ROUND(SUM(node_hours), 4) AS node_hours,
    MIN(dt_dag_run_started) AS dt_dag_run_started,
    provisioner,
    id_databricks_workspace,
    MIN(
        CASE id_databricks_workspace
            WHEN '4531937035440038' THEN 'QuintoAndar'
            WHEN '6170817193817'     THEN 'Prod'
            WHEN '4033397625841925'  THEN 'Forno'
            ELSE 'Unknown'
        END
    ) AS workspace_name,
    team_owner,
    airflow_dag_id,
    cost_cohort,
    dag_run_type
FROM
    slots
WHERE
    node_type IS NOT NULL
GROUP BY
    dt_period,
    REGEXP_EXTRACT(node_type, '^([a-z0-9]+)[.-]', 1),
    REGEXP_EXTRACT(node_type, '\.([a-z0-9]+)$', 1),
    provisioner,
    id_databricks_workspace,
    team_owner,
    airflow_dag_id,
    cost_cohort,
    dag_run_type
