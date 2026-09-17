-- ============================================================================
-- daily_resource_billed_cost.sql
--
-- Shared CUR-derived billed cost enrich. One row per
--   (dt_usage, id_aws_account, resource_kind, id_resource, market)
-- covering AmazonEC2 BoxUsage / SpotUsage / VolumeUsage and ElasticMapReduce
-- fee lines. Consumed by Databricks cost/health facts and EMR cluster-day
-- cost. DBU is untouched (not in CUR).
--
-- billed_cost_usd is amortized:
--   DiscountedUsage         -> reservation_effective_cost
--   SavingsPlanCoveredUsage -> savings_plan_savings_plan_effective_cost
--   else                    -> line_item_unblended_cost
-- SavingsPlanNegation is excluded: it exactly cancels CoveredUsage.
-- billed_cost_usd is gross of the enterprise discount and net_cost_usd is net of it.
--
-- Usage-type matches are '%BoxUsage%' / '%SpotUsage%' / '%VolumeUsage%' so
-- region-prefixed CUR tokens (e.g. USE1-BoxUsage:m5.large) are included.
-- usage_hours is gated on BoxUsage/SpotUsage so DataTransfer gigabytes are
-- not mixed into instance-hours.
--
-- ts_first_usage / ts_last_usage keep CUR's native hourly grain inside the
-- daily row. EMR cluster<->Airflow-run matching needs sub-day resolution: a
-- single DAG can open 48 runs in one calendar day, so a day-grain window
-- cannot tell those runs apart. Both are grain-safe aggregates of the
-- existing GROUP BY.
--
-- Partition prune: year/month are billing periods, not usage months, and
-- usage for day D can land in month D+1 — the year/month window extends
-- one calendar month past load_end_date. Forward-dated SP recurring-fee
-- phantoms are dropped with line_item_usage_start_date < CURRENT_DATE().
-- AmazonInspectorV2 rows also carry i- resource ids; the AmazonEC2 +
-- usage-type pin keeps them out.
--
-- Source: cost_usage_reports.aws_costs_new
-- ============================================================================
WITH cur_rows AS (
    SELECT
        DATE(line_item_usage_start_date)                              AS dt_usage,
        line_item_usage_account_id                                    AS id_aws_account,
        CASE
            WHEN line_item_product_code = 'ElasticMapReduce'
                 AND line_item_resource_id LIKE '%cluster/j-%'        THEN 'emr_fee'
            WHEN line_item_resource_id LIKE 'i-%'                     THEN 'ec2_instance'
            WHEN line_item_resource_id LIKE 'vol-%'                   THEN 'ebs_volume'
            ELSE 'other'
        END                                                           AS resource_kind,
        line_item_resource_id                                         AS id_resource,
        CASE
            WHEN line_item_usage_type LIKE '%SpotUsage%'              THEN 'spot'
            WHEN line_item_usage_type LIKE '%BoxUsage%'               THEN 'on_demand'
            ELSE 'not_applicable'
        END                                                           AS market,
        product_instance_type                                         AS instance_type,
        NULLIF(resource_tags_aws_elasticmapreduce_instance_group_role, '')
                                                                      AS instance_role,
        line_item_product_code                                        AS product_code,
        line_item_usage_amount                                        AS usage_amount,
        IF(
            line_item_usage_type LIKE '%BoxUsage%'
            OR line_item_usage_type LIKE '%SpotUsage%',
            line_item_usage_amount,
            CAST(0 AS DOUBLE)
        )                                                             AS usage_hours,
        line_item_usage_start_date                                    AS ts_usage_start,
        line_item_usage_end_date                                      AS ts_usage_end,
        CASE line_item_line_item_type
            WHEN 'DiscountedUsage'
                THEN COALESCE(reservation_effective_cost, 0)
            WHEN 'SavingsPlanCoveredUsage'
                THEN COALESCE(savings_plan_savings_plan_effective_cost, 0)
            ELSE COALESCE(line_item_unblended_cost, 0)
        END                                                           AS billed_cost_usd,
        CASE line_item_line_item_type
            WHEN 'DiscountedUsage'
                THEN COALESCE(reservation_net_effective_cost, reservation_effective_cost, 0)
            WHEN 'SavingsPlanCoveredUsage'
                THEN COALESCE(
                         savings_plan_net_savings_plan_effective_cost,
                         savings_plan_savings_plan_effective_cost,
                         0
                     )
            ELSE COALESCE(line_item_net_unblended_cost, line_item_unblended_cost, 0)
        END                                                           AS net_cost_usd,
        COALESCE(line_item_unblended_cost, 0)                         AS gross_cost_usd,
        COALESCE(pricing_public_on_demand_cost, 0)                    AS public_on_demand_cost_usd,
        line_item_line_item_type = 'DiscountedUsage'                  AS is_ri_covered,
        line_item_line_item_type = 'SavingsPlanCoveredUsage'          AS is_sp_covered,
        IF(
            resource_tags_user_vendor = 'Databricks',
            NULLIF(resource_tags_user_cluster_id, ''),
            NULL
        )                                                             AS id_databricks_cluster,
        COALESCE(
            NULLIF(resource_tags_aws_elasticmapreduce_job_flow_id, ''),
            IF(
                line_item_product_code = 'ElasticMapReduce',
                NULLIF(regexp_extract(line_item_resource_id, '(j-[A-Z0-9]+)', 1), ''),
                NULL
            )
        )                                                             AS id_emr_cluster,
        NULLIF(resource_tags_aws_elasticmapreduce_job_flow_id, '')    AS tag_job_flow_id,
        NULLIF(resource_tags_user_dag_id, '')                         AS tag_dag_id,
        NULLIF(resource_tags_user_vendor, '')                         AS tag_vendor,
        NULLIF(resource_tags_user_provisioner, '')                    AS tag_provisioner,
        NULLIF(resource_tags_user_app, '')                            AS tag_app,
        NULLIF(resource_tags_user_owner, '')                          AS tag_owner,
        NULLIF(resource_tags_user_environment, '')                    AS tag_environment,
        NULLIF(resource_tags_user_ecosystem, '')                      AS tag_ecosystem,
        NULLIF(resource_tags_user_cost_center, '')                    AS tag_cost_center,
        NULLIF(resource_tags_user_data_classification, '')            AS tag_data_classification,
        NULLIF(resource_tags_user_sensitive_data, '')                 AS tag_sensitive_data
    FROM
        cost_usage_reports.aws_costs_new
    WHERE
        (year * 100 + month) >= (YEAR(DATE('{load_start_date}')) * 100 + MONTH(DATE('{load_start_date}')))
        AND (year * 100 + month) <= (
            YEAR(ADD_MONTHS(DATE('{load_end_date}'), 1)) * 100
            + MONTH(ADD_MONTHS(DATE('{load_end_date}'), 1))
        )
        AND line_item_usage_start_date >= DATE('{load_start_date}')
        AND line_item_usage_start_date <  DATE('{load_end_date}')
        AND line_item_usage_start_date <  CURRENT_DATE()
        AND line_item_line_item_type IN ('Usage', 'DiscountedUsage', 'SavingsPlanCoveredUsage')
        AND (
                (
                    line_item_product_code = 'AmazonEC2'
                    AND (
                            line_item_usage_type LIKE '%BoxUsage%'
                         OR line_item_usage_type LIKE '%SpotUsage%'
                         OR line_item_usage_type LIKE '%VolumeUsage%'
                    )
                )
             OR line_item_product_code = 'ElasticMapReduce'
        )
)
SELECT
    XXHASH64(
        CAST(dt_usage AS STRING),
        COALESCE(id_aws_account, ''),
        resource_kind,
        COALESCE(id_resource, ''),
        market
    )                                                                 AS sk_resource_billed_cost,
    id_aws_account,
    resource_kind,
    id_resource,
    MAX(id_databricks_cluster)                                        AS id_databricks_cluster,
    MAX(id_emr_cluster)                                               AS id_emr_cluster,
    market,
    MAX(instance_type)                                                AS instance_type,
    MAX(instance_role)                                                AS instance_role,
    MAX(product_code)                                                 AS product_code,
    ROUND(SUM(usage_amount), 6)                                       AS usage_amount,
    ROUND(SUM(usage_hours), 6)                                        AS usage_hours,
    ROUND(SUM(billed_cost_usd), 4)                                    AS billed_cost_usd,
    ROUND(SUM(net_cost_usd), 4)                                       AS net_cost_usd,
    ROUND(SUM(billed_cost_usd) - SUM(net_cost_usd), 4)                AS discount_usd,
    ROUND(SUM(gross_cost_usd), 4)                                     AS gross_cost_usd,
    ROUND(SUM(public_on_demand_cost_usd), 4)                          AS public_on_demand_cost_usd,
    BOOL_OR(is_ri_covered)                                            AS is_ri_covered,
    BOOL_OR(is_sp_covered)                                            AS is_sp_covered,
    MAX(tag_job_flow_id)                                              AS tag_job_flow_id,
    MAX(tag_dag_id)                                                   AS tag_dag_id,
    MAX(tag_vendor)                                                   AS tag_vendor,
    MAX(tag_provisioner)                                              AS tag_provisioner,
    MAX(tag_app)                                                      AS tag_app,
    MAX(tag_owner)                                                    AS tag_owner,
    MAX(tag_environment)                                              AS tag_environment,
    MAX(tag_ecosystem)                                                AS tag_ecosystem,
    MAX(tag_cost_center)                                              AS tag_cost_center,
    MAX(tag_data_classification)                                      AS tag_data_classification,
    MAX(tag_sensitive_data)                                           AS tag_sensitive_data,
    MIN(ts_usage_start)                                               AS ts_first_usage,
    MAX(ts_usage_end)                                                 AS ts_last_usage,
    CURRENT_TIMESTAMP()                                               AS ts_load,
    dt_usage
FROM
    cur_rows
GROUP BY
    dt_usage,
    id_aws_account,
    resource_kind,
    id_resource,
    market
