SELECT
    BIGINT(ad_id) AS id_ad,
    BIGINT(account_id) AS id_account,
    BIGINT(adset_id) AS id_adset,
    BIGINT(campaign_id) AS id_campaign,
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
    DATE(date_start) AS dt_insights_range_started,
    DATE(date_stop) AS dt_insights_range_ended,
    SMALLINT(year) AS year,
    TINYINT(month) AS month,
    TINYINT(day) AS day
FROM
    datalake_casa_mineira_facebook_insights_raw.facebook_social_insights
WHERE
    date_start = DATE('{year}-{month}-{day}')