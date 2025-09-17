SELECT
    BIGINT(ad_id) AS id_ad,
    BIGINT(account_id) AS id_account,
    BIGINT(adset_id) AS id_adset,
    BIGINT(campaign_id) AS id_campaign,
    account_name,
    account_name_snake_case,
    CASE
        WHEN account_name_snake_case LIKE '%mx%' THEN 'MX'
        WHEN account_name_snake_case IS NULL THEN 'Undefined'
        ELSE 'BR'
    END AS country_code,
    ad_name,
    adset_name,
    campaign_name,
    region,
    INT(clicks) AS clicks,
    INT(impressions) AS impressions,
    INT(inline_link_clicks) AS inline_link_clicks,
    actions,
    DOUBLE(spend) AS spend,
    DATE(date_start) AS dt_start,
    DATE(date_stop) AS dt_stop,
    year,
    month,
    day
FROM
    datalake_facebook_insights_region_raw.facebook_insights_455006745173996_region
WHERE
    DATE(date_start) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
