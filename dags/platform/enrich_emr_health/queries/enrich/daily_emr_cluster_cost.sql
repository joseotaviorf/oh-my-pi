-- ============================================================================
-- daily_emr_cluster_cost.sql
--
-- Per-cluster-day billed AWS CUR cost for Airflow-orchestrated EMR clusters.
-- Grain: (dt_cluster_run, id_emr_cluster).
--
-- Identity comes from datalake_emr_health.emr_instance_timeline:
--   EC2  — join CUR ec2_instance rows on id_ec2_instance
--   EBS  — EXPLODE(ebs_volume_ids) join CUR ebs_volume rows on vol-…
--   fee  — join CUR emr_fee rows on id_emr_cluster (ARN-extracted)
--
-- Do not re-derive amortized USD here — billed_cost_usd is gross of the
-- enterprise discount and net_cost_usd is net of it; both are already
-- amortized in datalake_aws_billed_cost.daily_resource_billed_cost.
--
-- cost_source:
--   cur          — EC2 billed cost present (instance mapping worked)
--   cur_partial  — no EC2, but EBS and/or EMR fee present (fee-line fallback
--                  when ListInstances returned nothing)
--   missing      — timeline cluster-day with no matching CUR rows
-- Alphabetically MAX(cost_source) is worst-wins (missing > cur_partial > cur);
-- MIN would pick the best. Facts should CASE-rank, not MIN().
--
-- Window is 35 days before load_end_date (not the DAG's 2-day API lookback)
-- so AWS restatements of closed billing periods land the same way as
-- enrich_aws_billed_cost. Timeline partitions from prior runs are reused;
-- this query does not re-walk ListClusters.
-- ============================================================================
WITH timeline_days AS (
    SELECT
        dt_cluster_run,
        id_emr_cluster,
        id_ec2_instance,
        ebs_volume_ids,
        tag_owner,
        tag_cost_center,
        tag_ecosystem,
        tag_environment,
        tag_data_classification,
        tag_sensitive_data
    FROM
        datalake_emr_health.emr_instance_timeline
    WHERE
        dt_cluster_run >= DATE_SUB(DATE('{load_end_date}'), 35)
        AND dt_cluster_run <  DATE('{load_end_date}')
),
ec2_cost AS (
    SELECT
        t.dt_cluster_run,
        t.id_emr_cluster,
        ROUND(SUM(c.billed_cost_usd), 4) AS total_ec2_cost_usd,
        ROUND(SUM(c.net_cost_usd), 4)    AS total_ec2_net_cost_usd,
        ROUND(
            SUM(IF(c.market = 'on_demand', c.usage_hours, CAST(0 AS DOUBLE))),
            6
        )                                AS ec2_on_demand_hours,
        ROUND(
            SUM(IF(c.market = 'spot', c.usage_hours, CAST(0 AS DOUBLE))),
            6
        )                                AS ec2_spot_hours,
        MAX(t.tag_owner)                 AS tag_owner,
        MAX(t.tag_cost_center)           AS tag_cost_center,
        MAX(t.tag_ecosystem)             AS tag_ecosystem,
        MAX(t.tag_environment)           AS tag_environment,
        MAX(t.tag_data_classification)   AS tag_data_classification,
        MAX(t.tag_sensitive_data)        AS tag_sensitive_data
    FROM
        timeline_days AS t
    INNER JOIN
        datalake_aws_billed_cost.daily_resource_billed_cost AS c
            ON  c.resource_kind = 'ec2_instance'
            AND c.id_resource = t.id_ec2_instance
            AND c.dt_usage = t.dt_cluster_run
    GROUP BY
        t.dt_cluster_run,
        t.id_emr_cluster
),
ebs_volumes AS (
    SELECT DISTINCT
        t.dt_cluster_run,
        t.id_emr_cluster,
        EXPLODE(t.ebs_volume_ids) AS id_ebs_volume
    FROM
        timeline_days AS t
    WHERE
        t.ebs_volume_ids IS NOT NULL
),
ebs_cost AS (
    SELECT
        v.dt_cluster_run,
        v.id_emr_cluster,
        ROUND(SUM(c.billed_cost_usd), 4) AS total_ebs_cost_usd,
        ROUND(SUM(c.net_cost_usd), 4)    AS total_ebs_net_cost_usd
    FROM
        ebs_volumes AS v
    INNER JOIN
        datalake_aws_billed_cost.daily_resource_billed_cost AS c
            ON  c.resource_kind = 'ebs_volume'
            AND c.id_resource = v.id_ebs_volume
            AND c.dt_usage = v.dt_cluster_run
    GROUP BY
        v.dt_cluster_run,
        v.id_emr_cluster
),
fee_cost AS (
    SELECT
        c.dt_usage                       AS dt_cluster_run,
        c.id_emr_cluster,
        ROUND(SUM(c.billed_cost_usd), 4) AS total_emr_fee_cost_usd,
        ROUND(SUM(c.net_cost_usd), 4)    AS total_emr_fee_net_cost_usd,
        MAX(c.tag_owner)                 AS tag_owner,
        MAX(c.tag_cost_center)           AS tag_cost_center,
        MAX(c.tag_ecosystem)             AS tag_ecosystem,
        MAX(c.tag_environment)           AS tag_environment,
        MAX(c.tag_data_classification)   AS tag_data_classification,
        MAX(c.tag_sensitive_data)        AS tag_sensitive_data
    FROM
        datalake_aws_billed_cost.daily_resource_billed_cost AS c
    WHERE
        c.resource_kind = 'emr_fee'
        AND c.id_emr_cluster IS NOT NULL
        AND c.dt_usage >= DATE_SUB(DATE('{load_end_date}'), 35)
        AND c.dt_usage <  DATE('{load_end_date}')
        AND (
                c.tag_provisioner = 'emr'
             OR c.id_emr_cluster IN (
                    SELECT DISTINCT
                        id_emr_cluster
                    FROM
                        timeline_days
                )
        )
    GROUP BY
        c.dt_usage,
        c.id_emr_cluster
),
cluster_days AS (
    SELECT
        dt_cluster_run,
        id_emr_cluster
    FROM
        timeline_days
    UNION
    SELECT
        dt_cluster_run,
        id_emr_cluster
    FROM
        fee_cost
)
SELECT
    XXHASH64(
        CAST(d.dt_cluster_run AS STRING),
        d.id_emr_cluster
    )                                                    AS sk_emr_cluster_cost,
    d.id_emr_cluster,
    COALESCE(ec.total_ec2_cost_usd, 0)                   AS total_ec2_cost_usd,
    COALESCE(eb.total_ebs_cost_usd, 0)                   AS total_ebs_cost_usd,
    COALESCE(f.total_emr_fee_cost_usd, 0)                AS total_emr_fee_cost_usd,
    COALESCE(ec.total_ec2_net_cost_usd, 0)               AS total_ec2_net_cost_usd,
    COALESCE(eb.total_ebs_net_cost_usd, 0)               AS total_ebs_net_cost_usd,
    COALESCE(f.total_emr_fee_net_cost_usd, 0)            AS total_emr_fee_net_cost_usd,
    ROUND(
        COALESCE(ec.total_ec2_cost_usd, 0)
        + COALESCE(eb.total_ebs_cost_usd, 0)
        + COALESCE(f.total_emr_fee_cost_usd, 0)
        - COALESCE(ec.total_ec2_net_cost_usd, 0)
        - COALESCE(eb.total_ebs_net_cost_usd, 0)
        - COALESCE(f.total_emr_fee_net_cost_usd, 0),
        4
    )                                                    AS total_discount_usd,
    COALESCE(ec.tag_owner, f.tag_owner)                  AS tag_owner,
    COALESCE(ec.tag_cost_center, f.tag_cost_center)      AS tag_cost_center,
    COALESCE(ec.tag_ecosystem, f.tag_ecosystem)          AS tag_ecosystem,
    COALESCE(ec.tag_environment, f.tag_environment)      AS tag_environment,
    COALESCE(ec.tag_data_classification, f.tag_data_classification)
                                                         AS tag_data_classification,
    COALESCE(ec.tag_sensitive_data, f.tag_sensitive_data)
                                                         AS tag_sensitive_data,
    COALESCE(ec.ec2_on_demand_hours, 0)                  AS ec2_on_demand_hours,
    COALESCE(ec.ec2_spot_hours, 0)                       AS ec2_spot_hours,
    CASE
        WHEN ec.total_ec2_cost_usd IS NOT NULL THEN 'cur'
        WHEN eb.total_ebs_cost_usd IS NOT NULL
          OR f.total_emr_fee_cost_usd IS NOT NULL THEN 'cur_partial'
        ELSE 'missing'
    END                                                  AS cost_source,
    CURRENT_TIMESTAMP()                                  AS ts_load,
    d.dt_cluster_run
FROM
    cluster_days AS d
LEFT JOIN
    ec2_cost AS ec
        ON  ec.dt_cluster_run = d.dt_cluster_run
        AND ec.id_emr_cluster = d.id_emr_cluster
LEFT JOIN
    ebs_cost AS eb
        ON  eb.dt_cluster_run = d.dt_cluster_run
        AND eb.id_emr_cluster = d.id_emr_cluster
LEFT JOIN
    fee_cost AS f
        ON  f.dt_cluster_run = d.dt_cluster_run
        AND f.id_emr_cluster = d.id_emr_cluster
