SELECT
    BIGINT(ad_id) as id_ad,
    BIGINT(account_id) as id_account,
    BIGINT(adset_id) as id_adset,
    BIGINT(campaign_id) as id_campaign,
    ad_name,
    adset_name,
    campaign_name,
    INT(clicks) AS clicks,
    FLOAT(cpc) AS cpc,
    FLOAT(cpm) AS cpm,
    INT(impressions) AS impressions,
    platform_position,
    publisher_platform,
    INT(reach) AS reach,
    DATE(date_start) AS dt_start,
    DATE(date_stop) AS dt_stop,
    SMALLINT(year) AS year,
    TINYINT(month) AS month,
    TINYINT(day) AS day
FROM
    datalake_marketing_costs_raw.facebook_social_insights