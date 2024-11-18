WITH lookup AS (
SELECT 
    state,
    locality,
    start_range,
    MAX(end_range) AS end_range
FROM datalake_gsheets_clean.criteo_region_lookup
GROUP BY ALL
)

SELECT 
    -- Dimensions
    id_advertiser AS id_account,
    id_campaign,
    id_ad_set AS id_adset,
    NULL::STRING AS id_ad,
    advertiser_name AS account_name,
    'criteo' AS origin,
    'campaigns' AS report_type,
    campaign_name AS utm_campaign,
    ad_set AS utm_term,
    NULL::STRING AS utm_content,
    -- Regions
    'BR' AS country_code,
    cc.region AS state,
    lk.locality AS city,
    -- Metrics
    cc.clicks,
    NULL::BIGINT AS conversions,
    cc.displays AS impressions,
    cc.cost AS total_cost,
    -- Date Reference
    cc.dt_report AS dt_cost,
    YEAR(cc.dt_report) AS year,
    MONTH(cc.dt_report) AS month,
    DAY(cc.dt_report) AS day
FROM 
    datalake_criteo.criteo_campaigns AS cc
LEFT JOIN lookup AS lk
    ON cc.zip_code BETWEEN lk.start_range AND lk.end_range
WHERE 
    dt_report::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
