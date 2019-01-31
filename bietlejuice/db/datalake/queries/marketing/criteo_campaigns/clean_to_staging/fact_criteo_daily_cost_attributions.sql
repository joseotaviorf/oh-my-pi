SELECT
    cast(campaign_id as integer) as sk_criteo_campaign,
    cast(date_format(cast(cost_attribution_date as date), '%Y%m%d') as integer) as sk_cost_attribution_date,
    currency,
    cast(clicks as integer) as clicks,
    cast(impressions as double) as impressions,
    cast(audience as double) as audience,
    cast(cost as double) as cost,
    cast(all_sales as integer) as all_sales,
    cast(revenue as integer) as revenue,
    cast(composition_win as double) as composition_win,
    cast(cpc as double) as cpc
FROM datalake_clean.marketing_criteo_campaigns
WHERE dt_cost_attribution  = '{dt_cost_attribution}'