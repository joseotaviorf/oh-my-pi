WITH android_smartphone as (
    select ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as integer), 0)) as reach,
        sum(coalesce(cast(link_clicks as integer), 0)) as total_link_clicks,
        sum(coalesce(cast(spend as float), 0)) as spend,
        date_start,
        date_stop
    from staging.marketing_facebook_ads
    where impression_device = 'android_smartphone'
    group by 1,2,3,4,5,6,7,12,13
),
android_tablet as (
    select ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as integer), 0)) as reach,
        sum(coalesce(cast(link_clicks as integer), 0)) as total_link_clicks,
        sum(coalesce(cast(spend as float), 0)) as spend,
        date_start,
        date_stop
    from staging.marketing_facebook_ads
    where impression_device = 'android_tablet'
    group by 1,2,3,4,5,6,7,12,13
),
desktop as (
    select ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as integer), 0)) as reach,
        sum(coalesce(cast(link_clicks as integer), 0)) as total_link_clicks,
        sum(coalesce(cast(spend as float), 0)) as spend,
        date_start,
        date_stop
    from staging.marketing_facebook_ads
    where impression_device = 'desktop'
    group by 1,2,3,4,5,6,7,12,13
),
ipad as (
    select ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as integer), 0)) as reach,
        sum(coalesce(cast(link_clicks as integer), 0)) as total_link_clicks,
        sum(coalesce(cast(spend as float), 0)) as spend,
        date_start,
        date_stop
    from staging.marketing_facebook_ads
    where impression_device = 'ipad'
    group by 1,2,3,4,5,6,7,12,13
),
iphone as (
    select ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as integer), 0)) as reach,
        sum(coalesce(cast(link_clicks as integer), 0)) as total_link_clicks,
        sum(coalesce(cast(spend as float), 0)) as spend,
        date_start,
        date_stop
    from staging.marketing_facebook_ads
    where impression_device = 'iphone'
    group by 1,2,3,4,5,6,7,12,13
),
ipod as (
    select ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as integer), 0)) as reach,
        sum(coalesce(cast(link_clicks as integer), 0)) as total_link_clicks,
        sum(coalesce(cast(spend as float), 0)) as spend,
        date_start,
        date_stop
    from staging.marketing_facebook_ads
    where impression_device = 'ipod'
    group by 1,2,3,4,5,6,7,12,13
),
other as (
    select
        ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as integer), 0)) as reach,
        sum(coalesce(cast(link_clicks as integer), 0)) as total_link_clicks,
        sum(coalesce(cast(spend as float), 0)) as spend,
        date_start,
        date_stop
    from staging.marketing_facebook_ads
    where impression_device = 'other'
    group by 1,2,3,4,5,6,7,12,13
),
fact as (
    SELECT distinct min(ads.id) over (PARTITION BY ads.ad_id, ads.account_id, ads.campaign_id, ads.adset_id) as id,
        ads.ad_id,
        ads.account_id,
        ads.account_name,
        ads.campaign_id,
        ads.campaign_name,
        ads.adset_id,
        ads.adset_name,
        coalesce(android_smartphone.impressions, 0) as android_smartphone_impressions,
        coalesce(android_smartphone.reach, 0) as android_smartphone_reach,
        coalesce(android_smartphone.total_link_clicks, 0) as android_smartphone_total_link_clicks,
        coalesce(android_tablet.impressions, 0) as android_tablet_impressions,
        coalesce(android_tablet.reach, 0) as android_tablet_reach,
        coalesce(android_tablet.total_link_clicks, 0) as android_tablet_total_link_clicks,
        coalesce(desktop.impressions, 0) as desktop_impressions,
        coalesce(desktop.reach, 0) as desktop_reach,
        coalesce(desktop.total_link_clicks, 0) as desktop_total_link_clicks,
        coalesce(iphone.impressions, 0) as iphone_impressions,
        coalesce(iphone.reach, 0) as iphone_reach,
        coalesce(iphone.total_link_clicks, 0) as iphone_total_link_clicks,
        coalesce(ipad.impressions, 0) as ipad_impressions,
        coalesce(ipad.reach, 0) as ipad_reach,
        coalesce(ipad.total_link_clicks, 0) as ipad_total_link_clicks,
        coalesce(ipod.impressions, 0) as ipod_impressions,
        coalesce(ipod.reach, 0) as ipod_reach,
        coalesce(ipod.total_link_clicks, 0) as ipod_total_link_clicks,
        coalesce(other.impressions, 0) as other_impressions,
        coalesce(other.reach, 0) as other_reach,
        coalesce(other.total_link_clicks, 0) as other_total_link_clicks,
        (coalesce(android_smartphone.impressions, 0) + coalesce(android_tablet.impressions, 0) + coalesce(desktop.impressions, 0) + coalesce(iphone.impressions, 0) + coalesce(ipad.impressions, 0) + coalesce(ipod.impressions, 0) + coalesce(other.impressions, 0)) as total_impressions,
        (coalesce(android_smartphone.reach, 0) + coalesce(android_tablet.reach, 0) + coalesce(desktop.reach, 0) + coalesce(iphone.reach, 0) + coalesce(ipad.reach, 0) + coalesce(ipod.reach, 0) + coalesce(other.reach, 0)) as total_reach,
        (coalesce(android_smartphone.total_link_clicks, 0) + coalesce(android_tablet.total_link_clicks, 0) + coalesce(desktop.total_link_clicks, 0) + coalesce(iphone.total_link_clicks, 0) + coalesce(ipad.total_link_clicks, 0) + coalesce(ipod.total_link_clicks, 0) + coalesce(other.total_link_clicks, 0)) as total_link_clicks,
        (coalesce(android_smartphone.spend, 0) + coalesce(android_tablet.spend, 0) + coalesce(desktop.spend, 0) + coalesce(iphone.spend, 0) + coalesce(ipad.spend, 0) + coalesce(ipod.spend, 0) + coalesce(other.spend, 0)) as total_spend,
        ads.date_start,
        ads.date_stop,
        ads.acc
    FROM staging.marketing_facebook_ads ads
    LEFT JOIN android_smartphone
        ON android_smartphone.ad_id = ads.ad_id
            AND android_smartphone.account_id = ads.account_id
            AND android_smartphone.campaign_id = ads.campaign_id
            AND android_smartphone.adset_id = ads.adset_id
            AND android_smartphone.date_start = ads.date_start
            AND android_smartphone.date_stop = ads.date_stop
    LEFT JOIN android_tablet
        ON android_tablet.ad_id = ads.ad_id
            AND android_tablet.account_id = ads.account_id
            AND android_tablet.campaign_id = ads.campaign_id
            AND android_tablet.adset_id = ads.adset_id
            AND android_tablet.date_start = ads.date_start
            AND android_tablet.date_stop = ads.date_stop
    LEFT JOIN desktop
        ON desktop.ad_id = ads.ad_id
            AND desktop.account_id = ads.account_id
            AND desktop.campaign_id = ads.campaign_id
            AND desktop.adset_id = ads.adset_id
            AND desktop.date_start = ads.date_start
            AND desktop.date_stop = ads.date_stop
    LEFT JOIN ipad
        ON ipad.ad_id = ads.ad_id
            AND ipad.account_id = ads.account_id
            AND ipad.campaign_id = ads.campaign_id
            AND ipad.adset_id = ads.adset_id
            AND ipad.date_start = ads.date_start
            AND ipad.date_stop = ads.date_stop
    LEFT JOIN iphone
        ON iphone.ad_id = ads.ad_id
            AND iphone.account_id = ads.account_id
            AND iphone.campaign_id = ads.campaign_id
            AND iphone.adset_id = ads.adset_id
            AND iphone.date_start = ads.date_start
            AND iphone.date_stop = ads.date_stop
    LEFT JOIN ipod
        ON ipod.ad_id = ads.ad_id
            AND ipod.account_id = ads.account_id
            AND ipod.campaign_id = ads.campaign_id
            AND ipod.adset_id = ads.adset_id
            AND ipod.date_start = ads.date_start
            AND ipod.date_stop = ads.date_stop
    LEFT JOIN other
        ON other.ad_id = ads.ad_id
            AND other.account_id = ads.account_id
            AND other.campaign_id = ads.campaign_id
            AND other.adset_id = ads.adset_id
            AND other.date_start = ads.date_start
            AND other.date_stop = ads.date_stop
)
SELECT distinct
    coalesce(dim.sk_ad, fact.id) as sk_ad,
    fact.ad_id,
    to_char(fact.date_start::date, 'yyyyMMdd')::integer as sk_date_start,
    fact.account_id,
    fact.campaign_id,
    fact.adset_id,
    fact.android_smartphone_impressions,
    fact.android_smartphone_reach,
    fact.android_smartphone_total_link_clicks,
    fact.android_tablet_impressions,
    fact.android_tablet_reach,
    fact.android_tablet_total_link_clicks,
    fact.desktop_impressions,
    fact.desktop_reach,
    fact.desktop_total_link_clicks,
    fact.iphone_impressions,
    fact.iphone_reach,
    fact.iphone_total_link_clicks,
    fact.ipad_impressions,
    fact.ipad_reach,
    fact.ipad_total_link_clicks,
    fact.ipod_impressions,
    fact.ipod_reach,
    fact.ipod_total_link_clicks,
    fact.other_impressions,
    fact.other_reach,
    fact.other_total_link_clicks,
    fact.total_reach,
    fact.total_impressions,
    fact.total_link_clicks,
    fact.total_spend,
    getdate() as ts_load
from fact
left join staging.dim_facebook_ad dim
    on dim.ad_id = fact.ad_id
        and dim.account_name = fact.acc
        and dim.adset_name = fact.adset_name
        and dim.campaign_name = fact.campaign_name