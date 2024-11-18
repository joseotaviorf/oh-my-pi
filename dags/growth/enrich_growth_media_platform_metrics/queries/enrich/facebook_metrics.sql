SELECT 
    -- Dimensions
    id_account,
    id_campaign,
    id_adset,
    id_ad,
    account_name,
    'facebook' AS origin,
    'ads_insights_by_region' AS report_type,
    campaign_name AS utm_campaign,
    adset_name AS utm_term,
    ad_name AS utm_content,
    -- Regions
    country_code,
    regexp_replace(region, '\\(.*?\\)', '') AS state,
    NULL::STRING AS city, -- not available in the table
    -- Metrics
    clicks,
    NULL::BIGINT AS conversions,
    impressions,
    spend AS total_cost,
    -- Date Reference
    dt_start AS dt_cost,
    YEAR(dt_start) AS year,
    MONTH(dt_start) AS month,
    DAY(dt_start) AS day
FROM 
    datalake_facebook_insights_clean.facebook_ads_insights_by_region
WHERE 
    dt_start::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE