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
    SMALLINT(YEAR(date_start)) AS year,
    TINYINT(MONTH(date_start)) AS month,
    TINYINT(DAY(date_start)) AS day
FROM
    datalake_marketing_costs_raw.facebook_social_insights
WHERE
    date_start BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')