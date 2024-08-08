SELECT
    NULLIF(business, '') AS business_context,
    NULLIF(year_month, '') AS year_month,
    NULLIF(region, '') AS city_group,
    NULLIF(planning_conversion, '') AS planning_conversion,
    NULLIF(planning_operation, '') AS planning_operation,
    NULLIF(planning_cluster_adj, '') AS planning_cluster_adj,
    NULLIF(company_report_origin, '') AS company_report_origin,
    NULLIF(funnel_side, '') AS funnel_side,
    NULLIF(campaign_strategy_intent, '') AS campaign_strategy_intent,
    NULLIF(behavior_type, '') AS behavior_type,
    NULLIF(medium, '') AS medium,
    NULLIF(supply_medium, '') AS supply_medium,
    NULLIF(planning_mkt_level1, '') AS planning_mkt_level1,
    NULLIF(planning_mkt_level2, '') AS planning_mkt_level2,
    NULLIF(planning_mkt_level3, '') AS planning_mkt_level3,
    CAST(REPLACE(NULLIF(cost, ''), ',', '') AS FLOAT) AS cost,
    CAST(NULLIF(date, '') AS DATE) AS date
FROM
    datalake_gsheets_raw.forecast_costs_supply_daily