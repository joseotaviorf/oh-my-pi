SELECT
    NULLIF(side, '') AS side,
    NULLIF(city_group, '') AS city_group,
    NULLIF(account_name, '') AS account_name,
    NULLIF(campaign_name, '') AS campaign_name,
    NULLIF(ad_group_name, '') AS ad_group_name,
    NULLIF(utm_term, '') AS utm_term,
    NULLIF(utm_content, '') AS utm_content,
    NULLIF(mkt_business, '') AS mkt_business,
    NULLIF(mkt_origin, '') AS mkt_origin,
    NULLIF(mkt_channel, '') AS mkt_channel,
    NULLIF(mkt_medium, '') AS mkt_medium,
    NULLIF(mkt_source, '') AS mkt_source,
    CAST(NULLIF(cost, '') AS DOUBLE) AS cost,
    CAST(NULLIF(cost_share_mobile, '') AS DOUBLE) AS cost_share_mobile,
    CAST(NULLIF(cost_share_desktop, '') AS DOUBLE) AS cost_share_desktop,
    CAST(NULLIF(cost_share_other, '') AS DOUBLE) AS cost_share_other,
    DATE(NULLIF(dt, '')) AS dt
FROM
    datalake_gsheets_raw.casa_mineira_marketing_manual_shared_costs