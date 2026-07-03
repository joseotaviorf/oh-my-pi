-- Audit copy of Superset virtual dataset 22005 ("dag_health_cost_timeseries", dashboard 3969 /
-- TARS: DAG Health - Costs).
-- Deployed 2026-07-03 via PUT /api/v1/dataset/22005 (cost_cohort rollout).
-- Added airflow_dag_id + cost_cohort through filtered/bucketed/team_bucketed
-- and all three UNION branches as pass-through dimensions.
-- Any future edit to the live dataset MUST update this file in the same
-- change — untracked dataset edits caused the June-17 cost report incident.

-- Virtual dataset: dag_health_cost_timeseries
-- DBU/EC2 unpivot + team cost (charts filter on cost_layer).
-- Dimensions kept in GROUP BY so native filters see all provisioners.

WITH filtered AS (
    SELECT
        dt_dag_run_started,
        ts_run_started_min,
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
        total_cost_usd,
        total_dbu_cost_usd,
        total_ec2_cost_calculated_usd
    FROM
        delta.dw_databricks_health.fact_databricks_dag_run
    WHERE
        dt_dag_run_started >= DATE '2026-01-01'
),
bucketed AS (
    SELECT
        DATE_TRUNC('day', ts_run_started_min) AS dt_period,
        provisioner,
        id_databricks_workspace,
        workspace_name,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type,
        ROUND(SUM(total_dbu_cost_usd), 4) AS dbu_usd,
        ROUND(SUM(total_ec2_cost_calculated_usd), 4) AS ec2_usd,
        MIN(dt_dag_run_started) AS dt_dag_run_started
    FROM
        filtered
    GROUP BY
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8
),
team_bucketed AS (
    SELECT
        DATE_TRUNC('day', ts_run_started_min) AS dt_period,
        provisioner,
        id_databricks_workspace,
        workspace_name,
        COALESCE(team_owner, '(unassigned)') AS team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type,
        ROUND(SUM(total_cost_usd), 4) AS total_cost_usd,
        MIN(dt_dag_run_started) AS dt_dag_run_started
    FROM
        filtered
    GROUP BY
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8
)
SELECT
    dt_period,
    cost_layer,
    cost_component,
    cost_usd,
    dt_dag_run_started,
    provisioner,
    id_databricks_workspace,
    workspace_name,
    team_owner,
    airflow_dag_id,
    cost_cohort,
    dag_run_type
FROM (
    SELECT
        dt_period,
        'component' AS cost_layer,
        'DBU' AS cost_component,
        dbu_usd AS cost_usd,
        dt_dag_run_started,
        provisioner,
        id_databricks_workspace,
        workspace_name,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type
    FROM
        bucketed
    UNION ALL
    SELECT
        dt_period,
        'component' AS cost_layer,
        'EC2' AS cost_component,
        ec2_usd AS cost_usd,
        dt_dag_run_started,
        provisioner,
        id_databricks_workspace,
        workspace_name,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type
    FROM
        bucketed
    UNION ALL
    SELECT
        dt_period,
        'team' AS cost_layer,
        team_owner AS cost_component,
        total_cost_usd AS cost_usd,
        dt_dag_run_started,
        provisioner,
        id_databricks_workspace,
        workspace_name,
        team_owner,
        airflow_dag_id,
        cost_cohort,
        dag_run_type
    FROM
        team_bucketed
) AS stacked
