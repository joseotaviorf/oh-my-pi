SELECT 
    -- Dimensions
    ad_group.id_external_customer AS id_account,
    ad_group.id_campaign AS id_campaign,
    ad_group.id_ad_group AS id_adset,
    NULL::STRING AS id_ad,
    account_snake_case AS account_name,
    'google' AS origin,
    'ad_group_geo_performance' AS report_type,
    ad_group.campaign_name AS utm_campaign,
    ad_group.ad_group_name AS utm_term,
    NULL::STRING AS utm_content,
    -- Regions
    ad_group.country_code,
    CASE 
        WHEN (gt_region.name = 'Federal District') THEN 'Distrito Federal'
        ELSE regexp_replace(gt_region.name, '\^State of ', '')
    END AS state,
    gt_city.name AS city,
    -- Metrics
    ad_group.clicks,
    ad_group.conversions AS conversions,
    ad_group.impressions,
    (ad_group.cost/1000000) AS total_cost,
    -- Date Reference
    ad_group.dt_loaded AS dt_cost,
    YEAR(ad_group.dt_loaded) AS year,
    MONTH(ad_group.dt_loaded) AS month,
    DAY(ad_group.dt_loaded) AS day
FROM 
    datalake_google_ads_clean.ad_group_geo_performance AS ad_group
LEFT JOIN 
    datalake_google_ads_clean.geo_target_constant AS gt_city
    ON (ad_group.geoTargetCity = gt_city.resource_name)
LEFT JOIN 
    datalake_google_ads_clean.geo_target_constant AS gt_region
    ON (ad_group.geoTargetRegion = gt_region.resource_name)
WHERE 
    ad_group.dt_loaded::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE