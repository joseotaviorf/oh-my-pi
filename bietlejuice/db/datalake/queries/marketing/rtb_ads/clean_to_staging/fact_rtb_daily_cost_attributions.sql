SELECT
    sk_sub_campaign,
    sk_date,
    currency,
    clicks,
    impressions,
    ctr,
    cost,
    conversions_count,
    conversions_rate,
    cpc,
    ts_load
FROM (
    SELECT
        sta.sub_campaign_hash as sk_sub_campaign,
        cast(date_format(cast(sta.cost_attribution_date as date), '%Y%m%d') as integer) as sk_date,
        sta.account_currency as currency,
        cast(cast(sta.clicks_count as double)as integer) as clicks,
        cast(sta.impressions_count as double) as impressions,
        cast(sta.ctr as double) as ctr,
        cast(sta.cost as double) as cost,
        cast(sta.conversions_count as double) as conversions_count,
        cast(sta.cr as double) as conversions_rate,
        cast(sta.cpc as double) as cpc,
        current_timestamp as ts_load
    FROM datalake_clean.marketing_rtb_stats sta
)