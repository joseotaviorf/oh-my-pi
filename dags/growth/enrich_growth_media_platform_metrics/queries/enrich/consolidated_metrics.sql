WITH all_metrics AS (
    --  Facebook Metrics
    SELECT 
        *
    FROM 
        datalake_growth_media_platform.facebook_metrics
    WHERE 
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    UNION ALL
    -- Criteo Metrics
    SELECT 
        *
    FROM
        datalake_growth_media_platform.criteo_metrics
    WHERE 
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    -- Google Ads Metrics
    UNION ALL
    SELECT 
        *
    FROM
        datalake_growth_media_platform.google_metrics
    WHERE 
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    -- Trovit Metrics
    UNION ALL
    SELECT
        *
    FROM
        datalake_growth_media_platform.trovit_metrics
    WHERE
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
),
translation_dictionary AS (
    SELECT  
        account_name,
        campaign_name AS utm_campaign,
        origin,
        campaign_name_convention
    FROM 
        datalake_gsheets_clean.cost_taxonomy_translation_dictionary
    GROUP BY ALL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY account_name, campaign_name, origin ORDER BY campaign_name_convention) = 1
),
scd AS (
SELECT
  id_campaign,
  origin,
  IF(is_current = TRUE, campaign_name, NULL) AS current_campaign_name,
  LAG(campaign_name) OVER (PARTITION BY id_campaign, origin ORDER BY dt_start ASC) last_campaign_name,
  LAG(dt_end) OVER (PARTITION BY id_campaign, origin ORDER BY dt_start ASC) AS dt_campaign_name_last_change
FROM
  datalake_growth_media_platform.campaign_name_history
QUALIFY 
  current_campaign_name IS NOT NULL
),
region as (
SELECT 
  id AS id_region,
  SF_NORMALIZE_STRING(city_name) AS city_name_sanitized,
  city_group
FROM 
  datalake_region.region
QUALIFY 
  ROW_NUMBER() OVER (PARTITION BY city_name_sanitized ORDER BY id) = 1
)
SELECT 
    am.id_account,
    am.id_campaign,
    am.id_adset,
    am.id_ad,
    region.id_region,
    am.account_name,
    am.origin,
    am.report_type,
    am.utm_campaign,
    am.utm_term,
    am.utm_content,
    am.country_code,
    am.state,
    am.city,
    am.clicks,
    am.conversions,
    am.impressions,
    am.total_cost,
    CASE
        WHEN 
        td.campaign_name_convention IS NOT NULL 
        THEN 'sufix_from_dictionary'
        WHEN 
        NULLIF(CONCAT_WS('.', SLICE(SPLIT(am.utm_campaign, '[.]'), 2, 7)), '') IS NOT NULL 
        THEN 'sufix_from_campaign'
        ELSE 
        'not_mapped'
    END AS type_flow_media_setup,
    COALESCE(
        td.campaign_name_convention, -- sufix_from_dictionary,
        NULLIF(CONCAT_WS('.', SLICE(SPLIT(am.utm_campaign, '[.]'), 2, 7)), '') -- sufix_from_campaign
    ) AS name_convention_suffix,
    scd.current_campaign_name,
    scd.last_campaign_name,
    scd.dt_campaign_name_last_change,
    am.dt_cost,
    am.year,
    am.month,
    am.day
FROM 
    all_metrics AS am
LEFT JOIN 
    translation_dictionary AS td
        ON (am.origin = td.origin)
        AND (am.account_name = td.account_name)
        AND (am.utm_campaign = td.utm_campaign)
LEFT JOIN 
    scd 
        ON scd.id_campaign = am.id_campaign
        AND scd.origin = am.origin 
LEFT JOIN 
  region
        ON region.city_name_sanitized = SF_NORMALIZE_STRING(am.city)