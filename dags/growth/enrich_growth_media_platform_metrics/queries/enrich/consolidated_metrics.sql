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
        AND state != 'Unknown'
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
criteo_unknown_costs AS (
    SELECT
        dt_cost,
        id_campaign,
        id_adset,
        sum(case when state = 'Unknown' then total_cost end) as unknown_costs,
        sum(case when state = 'Unknown' then impressions end) as unknown_impressions,
        sum(case when state = 'Unknown' then clicks end) as unknown_clicks,
        sum(case when state != 'Unknown' then total_cost end) total_costs_without_unknown_costs,
        sum(case when state != 'Unknown' then impressions end) impressions_without_unknown_costs,
        sum(case when state != 'Unknown' then clicks end) clicks_without_unknown_costs
    FROM 
        datalake_growth_media_platform.criteo_metrics
    WHERE 
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    GROUP BY ALL
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
), 
base_costs as (
SELECT 
    am.id_account,
    am.id_campaign,
    am.id_adset,
    am.id_ad,
    CASE 
        WHEN city_group IS NULL AND state = 'Bahia' THEN 2922
        WHEN city_group IS NULL AND state = 'Santa Catarina' THEN 2039
        WHEN city_group IS NULL AND state IN ( 'Distrito Federal', 'Federal District' ) THEN 1514
        WHEN city_group IS NULL AND state IN ('Goiás', 'Goias', 'GoiÃ¡s')  THEN 1522
        WHEN city_group IS NULL AND state IN ('Paraná', 'Parana', 'ParanÃ¡')  THEN 1918
        WHEN city_group IS NULL AND state = 'Minas Gerais' THEN 1535
        WHEN city_group IS NULL AND state = 'Rio de Janeiro' THEN 1494
        WHEN city_group IS NULL AND state = 'Rio Grande do Sul' THEN 1842
        WHEN city_group IS NULL AND state in ('Sao Paulo', 'São Paulo', 'SÃ£o Paulo') THEN 39
    ELSE COALESCE(region.id_region, -1) END AS id_region,
    am.account_name,
    am.origin,
    am.report_type,
    am.utm_campaign,
    am.utm_term,
    am.utm_content,
    am.country_code,
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
    am.day,
    sum(am.clicks) AS clicks,
    sum(am.conversions) AS conversions,
    sum(am.impressions) AS impressions,
    sum(am.total_cost) AS total_cost
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
WHERE 
  (clicks > 0
  OR conversions > 0
  OR impressions > 0
  OR total_cost > 0)
GROUP BY ALL  
),
rateio_unknown_costs AS (
SELECT 
  bcn.id_campaign,
  bcn.id_adset,
  bcn.dt_cost,
  bcn.id_region,
  unknown_costs,
  total_costs_without_unknown_costs,
  unknown_impressions,
  unknown_clicks,
  impressions_without_unknown_costs,
  clicks_without_unknown_costs,
  CASE WHEN COALESCE(total_costs_without_unknown_costs,0.0) = 0 OR COALESCE(unknown_costs, 0.0) = 0 THEN 0 ELSE (SUM(total_cost) / total_costs_without_unknown_costs) * unknown_costs END as unknown_costs_city_group,
  CASE WHEN COALESCE(impressions_without_unknown_costs,0.0) = 0 OR COALESCE(unknown_impressions, 0.0) = 0 THEN 0 ELSE (SUM(impressions) / impressions_without_unknown_costs) * unknown_impressions END as unknown_impressions_city_group,
  CASE WHEN COALESCE(clicks_without_unknown_costs,0.0) = 0 OR COALESCE(unknown_clicks, 0.0) = 0 THEN 0 ELSE (SUM(clicks) / clicks_without_unknown_costs) * unknown_clicks END as unknown_clicks_city_group
FROM base_costs bcn 
  LEFT JOIN criteo_unknown_costs uc
    ON bcn.id_campaign = uc.id_campaign
    AND bcn.id_adset = uc.id_adset
    AND bcn.dt_cost = uc.dt_cost
WHERE origin = 'criteo'
GROUP BY ALL
)
SELECT
    bc.id_account,
    bc.id_campaign,
    bc.id_adset,
    bc.id_ad,
    bc.id_region,
    bc.account_name,
    bc.origin,
    bc.report_type,
    bc.utm_campaign,
    bc.utm_term,
    bc.utm_content,
    bc.country_code,
    bc.total_cost + coalesce(unknown_costs_city_group,0) AS total_cost,
    bc.impressions + coalesce(unknown_impressions_city_group, 0) AS impressions, 
    bc.clicks + coalesce(unknown_clicks_city_group, 0) AS clicks,
    bc.conversions,
    bc.name_convention_suffix,
    bc.current_campaign_name,
    bc.last_campaign_name,
    bc.dt_campaign_name_last_change,
    bc.dt_cost,
    bc.year,
    bc.month,
    bc.day
FROM base_costs bc  
    LEFT JOIN rateio_unknown_costs ruc 
        ON bc.id_campaign = ruc.id_campaign
        AND bc.id_adset = ruc.id_adset
        AND bc.dt_cost = ruc.dt_cost 
        AND bc.id_region = ruc.id_region
        AND bc.origin = 'criteo'