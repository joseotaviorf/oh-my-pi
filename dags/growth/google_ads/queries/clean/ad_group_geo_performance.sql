SELECT
    customer.id::BIGINT AS id_external_customer,
    campaign.id::BIGINT AS id_campaign,
    adgroup.id::BIGINT AS id_ad_group,
    campaign.name AS campaign_name,
    adgroup.name AS ad_group_name,
    metrics.clicks::BIGINT AS clicks,
    metrics.costMicros::DOUBLE AS cost,
    MONTH(segments.date::DATE) AS month,
    WEEKOFYEAR(segments.date::DATE) AS week,
    YEAR(segments.date::DATE) AS year,
    segments.device,
    segments.adNetworkType AS ad_network_type,
    metrics.impressions::BIGINT AS impressions,
    customer.descriptiveName AS account_descriptive_name,
    campaign.labels,
    report_type,
    account_snake_case,
    segments.geoTargetCity,
    segments.geoTargetRegion,
    CASE
        WHEN LOWER(account_snake_case) LIKE '%mx%' THEN 'MX'
        WHEN account_snake_case IS NULL THEN 'Undefined'
        ELSE 'BR'
    END AS country_code,
    segments.date::DATE AS dt_loaded,
    dt_created::DATE
FROM
    datalake_google_ads_raw.ad_group_geo_performance
WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
