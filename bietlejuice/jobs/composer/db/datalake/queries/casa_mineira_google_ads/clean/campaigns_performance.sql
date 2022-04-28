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
    INT(metrics.impressions) AS impressions,
    customer.descriptiveName AS account_descriptive_name,
    campaign.labels,
    report_type,
    account_snake_case,
    DATE(segments.date) AS dt_loaded,
    dt_created
FROM
    datalake_casa_mineira_google_ads_raw.campaigns_performance
WHERE
    DATE(dt_created) = DATE('{year}-{month}-{day}')
