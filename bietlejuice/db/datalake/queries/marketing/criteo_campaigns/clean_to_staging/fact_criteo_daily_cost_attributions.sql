SELECT (
    advertiser_name,
    campaign_id as sk_criteo_campaign,
    cast(date_format(cast(cost_attribution_date as date), '%Y%m%d') as integer) as sk_cost_attribution_date,
    currency,
    clicks,
    impressions,
    audience,
    cost,
    all_sales,
    revenue,
    composition_win,
    cpc,
)
FROM datalake_clean.marketing_criteo_campaigns
WHERE dt_cost_attribution  = '{dt_cost_attribution}'