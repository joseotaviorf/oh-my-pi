SELECT
    BIGINT(externalcustomerid) AS id_external_customer,
    BIGINT(campaignid) AS id_campaign,
    campaignname AS campaign_name,
    SMALLINT(clicks) AS clicks,
    double(cost) AS cost,
    TINYINT(month) AS month,
    TINYINT(week) AS week,
    TINYINT(year) AS year,
    device,
    INT(impressions) AS impressions,
    AccountDescriptiveName AS account_descriptive_name,
    labels,
    reporttype AS report_type,
    acc AS account_snake_case,
    DATE(`date`) AS dt_loaded,
    TO_DATE(dt, 'dd-MM-yyyy') AS dt_created
FROM
    datalake_google_ads_cm_raw.campaigns_performance_report
WHERE
    TO_DATE(dt, 'dd-MM-yyyy') = DATE('{year}-{month}-{day}')
