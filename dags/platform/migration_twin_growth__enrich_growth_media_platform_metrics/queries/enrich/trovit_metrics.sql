SELECT
    -- Dimensions
    id_account,
    id_campaign,
    NULL::STRING AS id_adset,
    NULL::STRING AS id_ad,
    account_name,
    'trovit' AS origin,
    'trovit_campaigns' AS report_type,
    REGEXP_REPLACE(campaign_name, '	', '') AS utm_campaign,
    NULL::STRING AS utm_term,
    NULL::STRING AS utm_content,
    -- Regions
    country_code,
    NULL::STRING AS state,
    NULL::STRING AS city, -- not available in the table
    -- Metrics
    clicks,
    NULL::BIGINT AS conversions,
    NULL::BIGINT impressions,
    total_cost,
    -- Date Reference
    dt_attribution AS dt_cost,
    YEAR(dt_cost) AS year,
    MONTH(dt_cost) AS month,
    DAY(dt_cost) AS day
FROM
    datalake_lifull_campaigns_clean.trovit_campaigns
WHERE
    dt_attribution::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE