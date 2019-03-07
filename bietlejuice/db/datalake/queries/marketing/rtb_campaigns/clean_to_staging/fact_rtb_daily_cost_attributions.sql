SELECT
    case when name='BR_QuintoAndar' then 1 else 0 end as sk_rtb_campaign,
    cast(date_format(cast(cost_attribution_date as date), '%Y%m%d') as integer) as sk_date,
    currency,
    cast(cast(clicks_count as double)as integer) as clicks,
    cast(impressions_count as double) as impressions,
    cast(ctr as double) as ctr,
    cast(campaign_cost as double) as cost,
    cast(conversions_count as double) as conversions_count,
    cast(conversions_rate as double) as conversions_rate,
    cast(cpc as double) as cpc,
    current_timestamp as ts_load
FROM datalake_clean.marketing_rtb_campaigns
WHERE dt_created  = '{date}' and acc = '{account}'