SELECT
    CAST(customer.id AS BIGINT) AS id_external_customer,
    CAST(campaign.id AS BIGINT) AS id_campaign,
    CAST(adgroup.id AS BIGINT) AS id_ad_group,
    campaign.name AS campaign_name,
    adgroup.name AS ad_group_name,
    CAST(metrics.clicks AS BIGINT) AS clicks,
    CAST(metrics.costMicros AS DOUBLE) AS cost,
    MONTH(CAST(segments.date AS DATE)) AS month,
    WEEKOFYEAR(CAST(segments.date AS DATE)) AS week,
    YEAR(CAST(segments.date AS DATE)) AS year,
    segments.device,
    segments.adNetworkType AS ad_network_type,
    CAST(metrics.impressions AS BIGINT) AS impressions,
    CAST(metrics.conversions AS BIGINT) AS conversions,
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
    CAST(segments.date AS DATE) AS dt_loaded,
    CAST(dt_created AS DATE)
FROM
    datalake_google_ads_raw.ad_group_geo_performance
WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
