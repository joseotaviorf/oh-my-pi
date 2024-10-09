SELECT
    BIGINT(customer.id) AS id_external_customer,
    BIGINT(campaign.id) AS id_campaign,
    campaign.name AS campaign_name,
    SMALLINT(metrics.clicks) AS clicks,
    DOUBLE(metrics.costMicros) AS cost,
    TINYINT(segments.month) AS MONTH,
    TINYINT(segments.week) AS week,
    TINYINT(segments.year) AS YEAR,
    segments.device,
    segments.adNetworkType AS ad_network_type,
    INT(metrics.impressions) AS impressions,
    customer.descriptiveName AS account_descriptive_name,
    campaign.labels,
    report_type,
    account_snake_case,
    CASE
        WHEN LOWER(account_snake_case) LIKE '%mx%' THEN 'MX'
        WHEN account_snake_case IS NULL THEN 'Undefined'
        ELSE 'BR'
    END AS country_code,
    DATE(segments.date) AS dt_loaded,
    dt_created
FROM
    datalake_google_ads_raw.campaigns_performance
WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
