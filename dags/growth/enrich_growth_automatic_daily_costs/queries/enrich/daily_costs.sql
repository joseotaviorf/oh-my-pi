SELECT
    cmm.id_date,
    'automatic' AS flow_type,
    cmm.origin,
    cmm.business_context,
    cmm.account_name,
    cmm.campaign_name,
    cmm.country_code,
    cmm.utm_campaign,
    cmm.utm_term,
    cmm.utm_content,
    cmm.city_group,
    COALESCE(msp.campaign_business_context, 'Not Mapped') AS campaign_business_context,
    COALESCE(msp.campaign_strategy_intent, 'Not Mapped') AS campaign_strategy_intent,
    COALESCE(msp.behavior_type, 'Not Mapped') AS behavior_type,
    COALESCE(msp.campaign_landing_page, 'Not Mapped') AS campaign_landing_page,
    COALESCE(msp.medium, 'Not Mapped') AS medium,
    COALESCE(msp.source, 'Not Mapped') AS source,
    COALESCE(msp.funnel_side, 'Not Mapped') AS funnel_side,
    cmm.total_cost, 
    cmm.impressions::FLOAT AS impressions, 
    cmm.clicks::FLOAT AS clicks
FROM
    datalake_consolidated_growth_metrics.consolidated_media_metrics cmm
LEFT JOIN
    datalake_growth_taxonomy.media_setup msp
ON
    cmm.campaign_name_convention_media_setup = msp.naming_convention_sufix
WHERE
    cmm.id_date BETWEEN INT(REPLACE('{load_start_date}', '-', ''))
    AND INT(REPLACE('{load_end_date}', '-', ''))
    AND cmm.total_cost != 0
    AND LOWER(SPLIT(cmm.campaign_name, '[.]') [0]) <> 'zebra'
