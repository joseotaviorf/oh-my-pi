SELECT
    -- Dimensions
    id_account,
    id_campaign,
    CAST(NULL AS STRING) AS id_adset,
    CAST(NULL AS STRING) AS id_ad,
    account_name,
    'trovit' AS origin,
    'trovit_campaigns' AS report_type,
    REGEXP_REPLACE(campaign_name, '	', '') AS utm_campaign,
    CAST(NULL AS STRING) AS utm_term,
    CAST(NULL AS STRING) AS utm_content,
    -- Regions
    country_code,
    CAST(NULL AS STRING) AS state,
    CAST(NULL AS STRING) AS city, -- not available in the table
    -- Metrics
    clicks,
    CAST(NULL AS BIGINT) AS conversions,
    CAST(NULL AS BIGINT) AS impressions,
    total_cost,
    -- Date Reference
    dt_attribution AS dt_cost,
    YEAR(dt_cost) AS year,
    MONTH(dt_cost) AS month,
    DAY(dt_cost) AS day
FROM
    datalake_lifull_campaigns_clean.trovit_campaigns
WHERE
    CAST(dt_attribution AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
