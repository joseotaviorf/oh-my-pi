SELECT
    NULLIF(rule_id, '') AS id_rule,
    NULLIF(side, '') AS side,
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
    CAST(REPLACE(NULLIF(cost, ''), ',', '') AS FLOAT) AS cost,
    CAST(REPLACE(NULLIF(cost_share_mobile, ''), ',', '') AS FLOAT) AS cost_share_mobile,
    CAST(REPLACE(NULLIF(cost_share_desktop, ''), ',', '') AS FLOAT) AS cost_share_desktop,
    CAST(REPLACE(NULLIF(cost_share_other, ''), ',', '') AS FLOAT) AS cost_share_other,
    CAST(NULLIF(dt, '') AS DATE) AS dt_cost
FROM
    datalake_marketing_manual_daily_costs_raw.marketing_costs_name_convention_shared_costs
