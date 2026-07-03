-- Audit copy of Superset virtual dataset 21205 ("dag_health_wow", dashboard 3969 /
-- TARS: DAG Health - Costs).
-- Deployed 2026-07-03 via PUT /api/v1/dataset/21205 (cost_cohort rollout).
-- Unchanged in this rollout: SELECT * passes the new cost_cohort column
-- through from metric_observability.dag_health_wow automatically.
-- Any future edit to the live dataset MUST update this file in the same
-- change — untracked dataset edits caused the June-17 cost report incident.

-- Virtual dataset: dag_health_wow
-- Latest WoW snapshot. Dimension filters come from dashboard native filters.

SELECT
    base.*,
    CASE
        WHEN REGEXP_LIKE(base.airflow_dag_id, '__validation$') THEN 'Validation DAG'
        ELSE 'Standard DAG'
    END AS dag_run_type
FROM (
    SELECT
        *
    FROM
        delta.metric_observability.dag_health_wow
    WHERE
        dt_window_end = (
            SELECT MAX(dt_window_end)
            FROM delta.metric_observability.dag_health_wow
        )
) AS base
