SELECT
    BIGINT(ad_id) AS id_ad,
    BIGINT(account_id) AS id_account,
    BIGINT(adset_id) AS id_adset,
    BIGINT(campaign_id) AS id_campaign,
    account_name,
    ad_name,
    adset_name,
    campaign_name,
    impression_device,
    INT(clicks) AS clicks,
    INT(impressions) AS impressions,
    INT(inline_link_clicks) AS inline_link_clicks,
    INT(reach) AS reach,
    DOUBLE(spend) AS spend,
    DATE(date_start) AS dt_insights_range_started,
    DATE(date_stop) AS dt_insights_range_ended,
    SMALLINT(year) AS year,
    TINYINT(month) AS month,
    TINYINT(day) AS day
FROM
    datalake_casa_mineira_facebook_insights_raw.facebook_insights
WHERE
    date_start = DATE('{year}-{month}-{day}')