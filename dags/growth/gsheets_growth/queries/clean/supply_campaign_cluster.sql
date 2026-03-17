SELECT
    CAST(NULLIF(campaign_strategy_intent, '') AS BIGINT) AS campaign_strategy_intent,
    CAST(NULLIF(campaign_business_context, '') AS BIGINT) AS campaign_business_context,
    CAST(NULLIF(source,'') AS STRING) AS source,
    CAST(NULLIF(medium,'') AS STRING) AS medium,
    CAST(NULLIF(behavior_type, '') AS DATE) AS behavior_type,
    CAST(NULLIF(funnel_side, '') AS DATE) AS funnel_side,
    CAST(NULLIF(campaign_landing_page, '') AS DATE) AS campaign_landing_page,
    CAST(NULLIF(campaign_cluster, '') AS DATE) AS campaign_cluster
FROM
    datalake_gsheets_raw.supply_campaign_cluster