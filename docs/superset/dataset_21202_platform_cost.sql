-- Audit copy of Superset virtual dataset 21202 ("Data Platform Cost - By Bucket"
-- family, dashboard 4027 / slug data-platform-cost-all-cohorts).
-- Deployed 2026-07-03 via PUT /api/v1/dataset/21202 (cost_cohort rollout).
-- The dataset now reads cost_cohort directly from
-- dw_databricks_costs.fact_databricks_costs (see dim_cost_cohort seed and
-- docs/cost_cohort_backfill.md); the former inline normalization + cohort CASE
-- were removed. Any future edit to the live dataset MUST update this file in
-- the same change — this audit copy exists because an untracked dataset edit
-- caused the June-17 cost report discrepancy.

WITH base AS (
    SELECT
        dt_usage,
        bucket,
        provisioner_resolved,
        id_databricks_workspace,
        CASE id_databricks_workspace
            WHEN '4531937035440038' THEN 'QuintoAndar'
            WHEN '6170817193817'     THEN 'Prod'
            WHEN '4033397625841925'  THEN 'Forno'
            ELSE 'Unknown'
        END                                                         AS workspace_name,
        COALESCE(environment, 'unknown')                            AS environment,
        COALESCE(team_owner, 'unknown')                             AS team_owner,
        COALESCE(cost_center, 'unknown')                            AS cost_center,
        COALESCE(ecosystem, 'unknown')                              AS ecosystem,
        compute_type,
        billing_origin_product,
        ec2_source,
        is_ec2_estimated,
        price_missing,
        dbu_cost_usd,
        ec2_cost_usd,
        total_cost_usd,
        dbu,
        cost_cohort
    FROM
        delta.dw_databricks_costs.fact_databricks_costs
    WHERE
        dt_usage >= DATE '2026-01-01'
),
daily AS (
    SELECT
        dt_usage,
        bucket,
        provisioner_resolved,
        id_databricks_workspace,
        workspace_name,
        environment,
        team_owner,
        cost_center,
        ecosystem,
        compute_type,
        billing_origin_product,
        ec2_source,
        is_ec2_estimated,
        price_missing,
        cost_cohort,
        ROUND(SUM(dbu_cost_usd), 4)                                 AS dbu_cost_usd,
        ROUND(SUM(ec2_cost_usd), 4)                                 AS ec2_cost_usd,
        ROUND(SUM(total_cost_usd), 4)                               AS total_cost_usd,
        ROUND(SUM(dbu), 4)                                          AS dbu
    FROM
        base
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
),
with_actuals AS (
    SELECT
        bucket,
        dt_usage AS dt_run,
        provisioner_resolved,
        id_databricks_workspace,
        workspace_name,
        environment,
        team_owner,
        cost_center,
        ecosystem,
        compute_type,
        billing_origin_product,
        ec2_source,
        is_ec2_estimated,
        price_missing,
        cost_cohort,
        dbu_cost_usd,
        ec2_cost_usd,
        total_cost_usd,
        dbu,
        CAST(0 AS DOUBLE)                                           AS projected_usd,
        CAST(0 AS DOUBLE)                                           AS projected_usd_cohort
    FROM
        daily
),
days_remaining AS (
    SELECT
        CAST(
            DATE_DIFF(
                'day',
                CURRENT_DATE,
                DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1' MONTH) - INTERVAL '1' DAY
            ) AS DOUBLE
        )                                                           AS days_remaining
),
trailing_7d_avg_bucket AS (
    SELECT
        bucket,
        AVG(daily_total)                                            AS daily_avg_7d
    FROM (
        SELECT
            bucket,
            dt_run,
            SUM(total_cost_usd)                                     AS daily_total
        FROM
            with_actuals
        WHERE
            dt_run >= CURRENT_DATE - INTERVAL '7' DAY
            AND dt_run < CURRENT_DATE
        GROUP BY
            bucket,
            dt_run
    ) daily_buckets
    GROUP BY
        bucket
),
trailing_7d_avg_cohort AS (
    SELECT
        cost_cohort,
        AVG(daily_total)                                            AS daily_avg_7d
    FROM (
        SELECT
            cost_cohort,
            dt_run,
            SUM(total_cost_usd)                                     AS daily_total
        FROM
            with_actuals
        WHERE
            dt_run >= CURRENT_DATE - INTERVAL '7' DAY
            AND dt_run < CURRENT_DATE
        GROUP BY
            cost_cohort,
            dt_run
    ) daily_cohorts
    GROUP BY
        cost_cohort
),
projection_bucket AS (
    SELECT
        t.bucket,
        CURRENT_DATE                                                AS dt_run,
        CAST(NULL AS VARCHAR)                                       AS provisioner_resolved,
        CAST(NULL AS VARCHAR)                                       AS id_databricks_workspace,
        CAST(NULL AS VARCHAR)                                       AS workspace_name,
        CAST(NULL AS VARCHAR)                                       AS environment,
        CAST(NULL AS VARCHAR)                                       AS team_owner,
        CAST(NULL AS VARCHAR)                                       AS cost_center,
        CAST(NULL AS VARCHAR)                                       AS ecosystem,
        CAST(NULL AS VARCHAR)                                       AS compute_type,
        CAST(NULL AS VARCHAR)                                       AS billing_origin_product,
        CAST(NULL AS VARCHAR)                                       AS ec2_source,
        FALSE                                                       AS is_ec2_estimated,
        FALSE                                                       AS price_missing,
        CAST(NULL AS VARCHAR)                                       AS cost_cohort,
        CAST(0 AS DOUBLE)                                           AS dbu_cost_usd,
        CAST(0 AS DOUBLE)                                           AS ec2_cost_usd,
        CAST(0 AS DOUBLE)                                           AS total_cost_usd,
        CAST(NULL AS DOUBLE)                                        AS dbu,
        ROUND(t.daily_avg_7d * d.days_remaining, 4)                 AS projected_usd,
        CAST(0 AS DOUBLE)                                           AS projected_usd_cohort
    FROM
        trailing_7d_avg_bucket AS t
    CROSS JOIN
        days_remaining AS d
    WHERE
        t.daily_avg_7d IS NOT NULL
),
projection_cohort AS (
    SELECT
        CAST(NULL AS VARCHAR)                                       AS bucket,
        CURRENT_DATE                                                AS dt_run,
        CAST(NULL AS VARCHAR)                                       AS provisioner_resolved,
        CAST(NULL AS VARCHAR)                                       AS id_databricks_workspace,
        CAST(NULL AS VARCHAR)                                       AS workspace_name,
        CAST(NULL AS VARCHAR)                                       AS environment,
        CAST(NULL AS VARCHAR)                                       AS team_owner,
        CAST(NULL AS VARCHAR)                                       AS cost_center,
        CAST(NULL AS VARCHAR)                                       AS ecosystem,
        CAST(NULL AS VARCHAR)                                       AS compute_type,
        CAST(NULL AS VARCHAR)                                       AS billing_origin_product,
        CAST(NULL AS VARCHAR)                                       AS ec2_source,
        FALSE                                                       AS is_ec2_estimated,
        FALSE                                                       AS price_missing,
        t.cost_cohort,
        CAST(0 AS DOUBLE)                                           AS dbu_cost_usd,
        CAST(0 AS DOUBLE)                                           AS ec2_cost_usd,
        CAST(0 AS DOUBLE)                                           AS total_cost_usd,
        CAST(NULL AS DOUBLE)                                        AS dbu,
        CAST(0 AS DOUBLE)                                           AS projected_usd,
        ROUND(t.daily_avg_7d * d.days_remaining, 4)                 AS projected_usd_cohort
    FROM
        trailing_7d_avg_cohort AS t
    CROSS JOIN
        days_remaining AS d
    WHERE
        t.daily_avg_7d IS NOT NULL
)
SELECT
    bucket, dt_run, provisioner_resolved, id_databricks_workspace, workspace_name,
    environment, team_owner, cost_center, ecosystem, compute_type, billing_origin_product,
    ec2_source, is_ec2_estimated, price_missing, cost_cohort,
    dbu_cost_usd, ec2_cost_usd, total_cost_usd, dbu, projected_usd, projected_usd_cohort
FROM
    with_actuals
UNION ALL
SELECT
    bucket, dt_run, provisioner_resolved, id_databricks_workspace, workspace_name,
    environment, team_owner, cost_center, ecosystem, compute_type, billing_origin_product,
    ec2_source, is_ec2_estimated, price_missing, cost_cohort,
    dbu_cost_usd, ec2_cost_usd, total_cost_usd, dbu, projected_usd, projected_usd_cohort
FROM
    projection_bucket
UNION ALL
SELECT
    bucket, dt_run, provisioner_resolved, id_databricks_workspace, workspace_name,
    environment, team_owner, cost_center, ecosystem, compute_type, billing_origin_product,
    ec2_source, is_ec2_estimated, price_missing, cost_cohort,
    dbu_cost_usd, ec2_cost_usd, total_cost_usd, dbu, projected_usd, projected_usd_cohort
FROM
    projection_cohort