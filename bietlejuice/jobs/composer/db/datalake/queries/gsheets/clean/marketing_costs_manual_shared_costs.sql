SELECT
    side,
    city_group,
    account_name,
    campaign_name,
    ad_group_name,
    utm_term,
    utm_content,
    mkt_business,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(cost AS FLOAT) AS cost,
    CAST(cost_share_mobile AS FLOAT) AS cost_share_mobile,
    CAST(cost_share_desktop AS FLOAT) AS cost_share_desktop,
    CAST(cost_share_other AS FLOAT) AS cost_share_other,
    CAST(dt AS DATE) AS dt_cost
FROM
    datalake_gsheets_raw.marketing_costs_manual_shared_costs