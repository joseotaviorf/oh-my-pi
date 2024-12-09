SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(funnel_side, '') AS funnel_side,
    NULLIF(operation_channel, '') AS operation_channel,
    NULLIF(referral_type, '') AS referral_type,
    NULLIF(campaign_strategy_intent, '') AS campaign_strategy_intent, 
    NULLIF(behavior_type, '') AS behavior_type,    
    NULLIF(medium, '') AS medium,    
    CAST(REPLACE(NULLIF(ntp, ''), ',', '') AS FLOAT) AS ntp,
    CAST(REPLACE(NULLIF(rtp, ''), ',', '') AS FLOAT) AS rtp,
    CAST(NULLIF(date, '') AS DATE) AS date
FROM
    datalake_gsheets_raw.rental_tenant_prospects_budget_2025