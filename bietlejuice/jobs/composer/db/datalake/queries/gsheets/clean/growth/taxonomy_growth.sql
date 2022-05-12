SELECT
    affiliate_type,
    lead_origin,
    lead_referring_category,
    lead_tracking_medium,
    lead_tracking_source,
    lead_type,
    mkt_channel,
    mkt_medium,
    mkt_origin,
    mkt_source,
    CAST(is_agent_referral AS BOOLEAN) AS is_agent_referral,
    CAST(is_branded AS BOOLEAN) AS is_branded,
    CAST(is_ops_direct_register AS BOOLEAN) AS is_ops_direct_register
FROM
    datalake_gsheets_raw.taxonomy_growth