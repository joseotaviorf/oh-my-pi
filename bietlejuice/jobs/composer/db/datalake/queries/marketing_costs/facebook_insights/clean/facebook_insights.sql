select
    bigint(ad_id) as id_ad,
    bigint(account_id) as id_account,
    bigint(adset_id) as id_adset,
    bigint(campaign_id) as id_campaign,
    account_name,
    ad_name,
    adset_name,
    campaign_name,
    impression_device,
    int(clicks) as clicks,
    int(impressions) as impressions,
    int(inline_link_clicks) as inline_link_clicks,
    int(reach) as reach,
    int(spend) as spend,
    smallint({year}) as year,
    tinyint({month}) as month,
    tinyint({day}) as day,
    date(date_start) as dt_start,
    date(date_stop) as dt_stop
from
    datalake_marketing_costs_raw.facebook_insights
where
    date_start = date('{year}-{month}-{day}')