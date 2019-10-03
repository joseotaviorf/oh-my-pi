with rtb_campaigns as (
    select distinct
        cam.hash,
        cam.account_currency
    from datalake_clean.marketing_rtb_sub_campaigns as cam
)
select
    sk_sub_campaign,
    sk_date,
    device,
    currency,
    clicks,
    impressions,
    ctr,
    cost,
    conversions_count,
    conversions_rate,
    cpc,
    ts_load
from (
    SELECT
        cam.hash as sk_sub_campaign,
        cast(date_format(cast(sta.cost_attribution_date as date), '%Y%m%d') as integer) as sk_date,
        case when upper(sta.device_type)='PC' then 'Desktop'
             when upper(sta.device_type)='UNKNOWN' then 'Other'
             when sta.device_type is not null and sta.device_type <> '' then 'Mobile'
             else 'Other'
         end as device,
        cam.account_currency as currency,
        cast(cast(sta.clicks_count as double)as integer) as clicks,
        cast(sta.impressions_count as double) as impressions,
        cast(sta.ctr as double) as ctr,
        cast(sta.cost as double) as cost,
        cast(sta.conversions_count as double) as conversions_count,
        cast(sta.cr as double) as conversions_rate,
        cast(sta.cpc as double) as cpc,
        current_timestamp as ts_load
    FROM datalake_clean.marketing_rtb_stats sta
    join rtb_campaigns as cam
        -- stats without campaign are mapped to RMSP (kwKe)
        on cam.hash = coalesce(sta.sub_campaign_hash, 'kwKe')
)