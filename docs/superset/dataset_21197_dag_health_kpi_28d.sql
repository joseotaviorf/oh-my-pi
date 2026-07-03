-- Audit copy of Superset virtual dataset 21197 ("dag_health_kpi_28d", dashboard 3969 /
-- TARS: DAG Health - Costs).
-- Deployed 2026-07-03 via PUT /api/v1/dataset/21197 (cost_cohort rollout).
-- Added airflow_dag_id + cost_cohort as GROUP BY dimensions (metrics are
-- distributive SUMs, so the grain widening is aggregation-safe).
-- Any future edit to the live dataset MUST update this file in the same
-- change — untracked dataset edits caused the June-17 cost report incident.

-- Virtual dataset: dag_health_kpi_28d
-- Trailing 28-day KPIs at filter grain (provisioner × workspace × team × dag × cohort × dag_run_type).

SELECT
    provisioner,
    id_databricks_workspace,
    CASE id_databricks_workspace
        WHEN '4531937035440038' THEN 'QuintoAndar'
        WHEN '6170817193817'     THEN 'Prod'
        WHEN '4033397625841925'  THEN 'Forno'
        ELSE 'Unknown'
    END AS workspace_name,
    team_owner,
    airflow_dag_id,
    cost_cohort,
    CASE
        WHEN REGEXP_LIKE(airflow_dag_id, '__validation$') THEN 'Validation DAG'
        ELSE 'Standard DAG'
    END AS dag_run_type,
    SUM(total_cost_usd) AS total_cost_usd,
    SUM(total_dbu_cost_usd) AS total_dbu_cost_usd,
    SUM(total_ec2_cost_calculated_usd) AS total_ec2_cost_calculated_usd,
    MIN(dt_dag_run_started) AS dt_dag_run_started
FROM
    delta.dw_databricks_health.fact_databricks_dag_run
WHERE
    dt_dag_run_started >= CURRENT_DATE - INTERVAL '27' DAY
    AND dt_dag_run_started <= CURRENT_DATE
GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7
