SELECT
    BIGINT(customer.id) AS id_external_customer,
    video.id AS id_video,
    BIGINT(adGroup.id) AS id_ad_group,
    BIGINT(campaign.id) AS id_campaign,
    adGroup.name AS ad_group_name,
    campaign.name AS campaign_name,
    metrics.clicks AS clicks,
    metrics.costMicros AS cost,
    segments.device AS device,
    segments.adNetworkType AS ad_network_type,
    metrics.impressions AS impressions,
    customer.descriptiveName AS account_descriptive_name,
    account_snake_case,
    CASE
        WHEN LOWER(account_snake_case) LIKE '%mx%' THEN 'MX'
        WHEN account_snake_case IS NULL THEN 'Undefined'
        ELSE 'BR'
    END AS country_code,
    report_type,
    DATE(segments.date) AS dt_loaded,
    dt_created
FROM
    datalake_google_ads_raw.videos_performance
WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
