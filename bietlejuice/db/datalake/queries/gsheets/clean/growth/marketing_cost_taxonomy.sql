SELECT
    NULLIF(TRIM(account_name), '') AS account_name,
    NULLIF(TRIM(report_type), '') AS report_type,
    NULLIF(TRIM(ad_type), '') AS ad_type,
    NULLIF(TRIM(campaign_origin_aquisition), '') AS campaign_origin_acquisition,
    NULLIF(TRIM(origin), '') AS origin,
    NULLIF(side, '') AS side,
    NULLIF(mkt_category, '') AS mkt_category,
    NULLIF(mkt_flow, '') AS mkt_flow,
    NULLIF(mkt_completion, '') AS mkt_completion,
    NULLIF(mkt_origin, '') AS mkt_origin,
    NULLIF(mkt_channel, '') AS mkt_channel,
    NULLIF(mkt_medium, '') AS mkt_medium,
    NULLIF(mkt_source, '') AS mkt_source,
    NULLIF(cost_factor, '') AS cost_factor
FROM datalake_gsheets_raw.marketing_cost_taxonomy
