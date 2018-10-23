WITH android_smartphone as (
    select ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as float), 0)) as reach,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        date_start,
        date_stop
    from staging.marketing_facebook_ads_ads_insights
    where impression_device = 'android_smartphone'
    group by 1,2,3,4,5,6,7,11,12
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
        sum(coalesce(cast(reach as float), 0)) as reach,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        date_start,
        date_stop
    from staging.marketing_facebook_ads_ads_insights
    where impression_device = 'android_tablet'
    group by 1,2,3,4,5,6,7,11,12
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
        sum(coalesce(cast(reach as float), 0)) as reach,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        date_start,
        date_stop
    from staging.marketing_facebook_ads_ads_insights
    where impression_device = 'desktop'
    group by 1,2,3,4,5,6,7,11,12
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
        sum(coalesce(cast(reach as float), 0)) as reach,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        date_start,
        date_stop
    from staging.marketing_facebook_ads_ads_insights
    where impression_device = 'ipad'
    group by 1,2,3,4,5,6,7,11,12
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
        sum(coalesce(cast(reach as float), 0)) as reach,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        date_start,
        date_stop
    from staging.marketing_facebook_ads_ads_insights
    where impression_device = 'iphone'
    group by 1,2,3,4,5,6,7,11,12
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
        sum(coalesce(cast(reach as float), 0)) as reach,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        date_start,
        date_stop
    from staging.marketing_facebook_ads_ads_insights
    where impression_device = 'ipod'
    group by 1,2,3,4,5,6,7,11,12
),
other as (
    select
        id,
        ad_id,
        account_id,
        campaign_id,
        adset_id,
        campaign_name,
        ad_name,
        impression_device,
        sum(coalesce(cast(impressions as float), 0)) as impressions,
        sum(coalesce(cast(reach as float), 0)) as reach,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        date_start,
        date_stop
    from staging.marketing_facebook_ads_ads_insights
    where impression_device = 'other'
    group by 1,2,3,4,5,6,7,11,12
),
ads as (
    select
        id as sk_ad,
        ad_id,
        account_id,
        campaign_id,
        adset_id,
        sum(coalesce(cast(reach as float), 0)) as total_reach,
        sum(coalesce(cast(impressions as float), 0)) as total_impressions,
        sum(coalesce(cast(clicks as float), 0)) as total_clicks,
        sum(coalesce(cast(spend as float), 0)) as total_spend,
        date_start as sk_date_start,
        date_stop as sk_date_stop,
        acc,
        dt_created
    from staging.marketing_facebook_ads_ads_insights
    group by 1,2,3,4,9,10,11,12
)
SELECT ads.sk_ad,
    ads.account_id,
    ads.campaign_id,
    ads.adset_id,
    cast(coalesce(android_smartphone.impressions, 0) as integer) as android_smartphone_impressions,
    cast(coalesce(android_smartphone.reach, 0) as integer) as android_smartphone_reach,
    cast(coalesce(android_smartphone.total_clicks, 0) as integer) as android_smartphone_total_clicks,
    cast(coalesce(android_tablet.impressions, 0) as integer) as android_tablet_impressions,
    cast(coalesce(android_tablet.reach, 0) as integer) as android_tablet_reach,
    cast(coalesce(android_tablet.total_clicks, 0) as integer) as android_tablet_total_clicks,
    cast(coalesce(desktop.impressions, 0) as integer) as desktop_impressions,
    cast(coalesce(desktop.reach, 0) as integer) as desktop_reach,
    cast(coalesce(desktop.total_clicks, 0) as integer) as desktop_total_clicks,
    cast(coalesce(iphone.impressions, 0) as integer) as iphone_impressions,
    cast(coalesce(iphone.reach, 0) as integer) as iphone_reach,
    cast(coalesce(iphone.total_clicks, 0) as integer) as iphone_total_clicks,
    cast(coalesce(ipad.impressions, 0) as integer) as ipad_impressions,
    cast(coalesce(ipad.reach, 0) as integer) as ipad_reach,
    cast(coalesce(ipad.total_clicks, 0) as integer) as ipad_total_clicks,
    cast(coalesce(ipod.impressions, 0) as integer) as ipod_impressions,
    cast(coalesce(ipod.reach, 0) as integer) as ipod_reach,
    cast(coalesce(ipod.total_clicks, 0) as integer) as ipod_total_clicks,
    cast(coalesce(other.impressions, 0) as integer) as other_impressions,
    cast(coalesce(other.reach, 0) as integer) as other_reach,
    cast(coalesce(other.total_clicks, 0) as integer) as other_total_clicks,
    cast(ads.total_reach as integer) as total_reach,
    cast(ads.total_impressions as integer) as total_impressions,
    cast(ads.total_clicks as integer) as total_clicks,
    ads.total_spend,
    ads.sk_date_start,
    ads.sk_date_stop
FROM ads
LEFT JOIN android_smartphone
    ON android_smartphone.ad_id = ads.sk_ad
        AND android_smartphone.account_id = ads.account_id
        AND android_smartphone.campaign_id = ads.campaign_id
        AND android_smartphone.adset_id = ads.adset_id
        AND android_smartphone.date_start = ads.sk_date_start
        AND android_smartphone.date_stop = ads.sk_date_stop
LEFT JOIN android_tablet
    ON android_tablet.ad_id = ads.sk_ad
        AND android_tablet.account_id = ads.account_id
        AND android_tablet.campaign_id = ads.campaign_id
        AND android_tablet.adset_id = ads.adset_id
        AND android_tablet.date_start = ads.sk_date_start
        AND android_tablet.date_stop = ads.sk_date_stop
LEFT JOIN desktop
    ON desktop.ad_id = ads.sk_ad
        AND desktop.account_id = ads.account_id
        AND desktop.campaign_id = ads.campaign_id
        AND desktop.adset_id = ads.adset_id
        AND desktop.date_start = ads.sk_date_start
        AND desktop.date_stop = ads.sk_date_stop
LEFT JOIN ipad
    ON ipad.ad_id = ads.sk_ad
        AND ipad.account_id = ads.account_id
        AND ipad.campaign_id = ads.campaign_id
        AND ipad.adset_id = ads.adset_id
        AND ipad.date_start = ads.sk_date_start
        AND ipad.date_stop = ads.sk_date_stop
LEFT JOIN iphone
    ON iphone.ad_id = ads.sk_ad
        AND iphone.account_id = ads.account_id
        AND iphone.campaign_id = ads.campaign_id
        AND iphone.adset_id = ads.adset_id
        AND iphone.date_start = ads.sk_date_start
        AND iphone.date_stop = ads.sk_date_stop
LEFT JOIN ipod
    ON ipod.ad_id = ads.sk_ad
        AND ipod.account_id = ads.account_id
        AND ipod.campaign_id = ads.campaign_id
        AND ipod.adset_id = ads.adset_id
        AND ipod.date_start = ads.sk_date_start
        AND ipod.date_stop = ads.sk_date_stop
LEFT JOIN other
    ON other.ad_id = ads.sk_ad
        AND other.account_id = ads.account_id
        AND other.campaign_id = ads.campaign_id
        AND other.adset_id = ads.adset_id
        AND other.date_start = ads.sk_date_start
        AND other.date_stop = ads.sk_date_stop