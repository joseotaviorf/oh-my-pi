SELECT
    NULLIF(tier, '') AS tier,
    NULLIF(city_group, '') AS city_group,
    NULLIF(mkt_origin, '') AS mkt_origin,
    NULLIF(mkt_channel, '') AS mkt_channel,
    NULLIF(medium, '') AS mkt_medium,
    NULLIF(mkt_source, '') AS mkt_source,
    NULLIF(funnel_side, '') AS funnel_side,
    NULLIF(operation_channel, '') AS operation_channel,
    NULLIF(referral_type, '') AS referral_type,
    NULLIF(campaign_strategy_intent, '') AS campaign_strategy_intent,
    NULLIF(behavior_type, '') AS behavior_type,
    CAST(REPLACE(ntp, ',', '') AS DECIMAL(16,4)) AS ntp_target,
    CAST(REPLACE(rtp, ',', '') AS DECIMAL(16,4)) AS rtp_target,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_budget
FROM
    datalake_gsheets_raw.rental_tenant_prospects_budget_2024