SELECT
    BIGINT(ad_id) AS id_ad,
    BIGINT(account_id) AS id_account,
    BIGINT(adset_id) AS id_adset,
    BIGINT(campaign_id) AS id_campaign,
    account_name,
    account_name_snake_case,
    ad_name,
    adset_name,
    campaign_name,
    impression_device,
    INT(clicks) AS clicks,
    INT(impressions) AS impressions,
    INT(inline_link_clicks) AS inline_link_clicks,
    INT(reach) AS reach,
    DOUBLE(spend) AS spend,
    SMALLINT(YEAR(date_start)) AS year,
    TINYINT(MONTH(date_start)) AS month,
    TINYINT(DAY(date_start)) AS day,
    DATE(date_start) AS dt_start,
    DATE(date_stop) AS dt_stop
FROM
    datalake_facebook_insights_raw.facebook_insights
WHERE
    date_start BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')