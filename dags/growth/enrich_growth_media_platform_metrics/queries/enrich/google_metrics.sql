WITH 
aggregated_google_report AS (
    SELECT
        id_external_customer AS id_account,
        id_campaign,
        id_ad_group AS id_adset,
        account_snake_case,
        'ad_group_geo_performance' AS report_type,
        campaign_name AS utm_campaign,
        ad_group_name AS utm_term,
        country_code,
        geoTargetCity AS geo_target_city,
        geoTargetRegion AS geo_target_region,
        clicks,
        conversions,
        impressions,
        (cost / 1000000) AS total_cost,
        dt_loaded AS dt_cost
    FROM
        datalake_google_ads_clean.ad_group_geo_performance
    WHERE
        dt_loaded::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
        AND (clicks > 0 OR impressions > 0 OR cost > 0)
    UNION ALL
    SELECT
        id_external_customer AS id_account,
        id_campaign,
        NULL AS id_adset, 
        account_snake_case,
        'campaigns_geo_performance' AS report_type,
        campaign_name AS utm_campaign,
        NULL AS utm_term,
        country_code,
        geo_target_city,
        geo_target_region,
        clicks,
        conversions,
        impressions,
        (cost / 1000000) AS total_cost,
        dt_loaded AS dt_cost
    FROM
        datalake_google_ads_clean.campaigns_geo_performance
    WHERE
        dt_loaded::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
        AND (clicks > 0 OR impressions > 0 OR cost > 0)
        AND id_campaign NOT IN (
            SELECT DISTINCT 
                id_campaign
            FROM 
                datalake_google_ads_clean.ad_group_geo_performance
            WHERE 
                dt_loaded::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
        )
)
SELECT 
    -- Dimensions
    aggregated.id_account,
    aggregated.id_campaign,
    aggregated.id_adset,
    NULL::STRING AS id_ad,
    aggregated.account_snake_case AS account_name,
    'google' AS origin,
    report_type,
    aggregated.utm_campaign,
    aggregated.utm_term,
    NULL::STRING AS utm_content,
    -- Regions
    aggregated.country_code,
    CASE 
        WHEN (gt_region.name = 'Federal District') THEN 'Distrito Federal'
        ELSE regexp_replace(gt_region.name, '\^State of ', '')
    END AS state,
    gt_city.name AS city,
    -- Metrics
    aggregated.clicks,
    aggregated.conversions AS conversions,
    aggregated.impressions,
    aggregated.total_cost,
    -- Date Reference
    aggregated.dt_cost,
    YEAR(aggregated.dt_cost) AS year,
    MONTH(aggregated.dt_cost) AS month,
    DAY(aggregated.dt_cost) AS day
FROM 
    aggregated_google_report aggregated
LEFT JOIN 
    datalake_google_ads_clean.geo_target_constant AS gt_city
    ON aggregated.geo_target_city = gt_city.resource_name
LEFT JOIN 
    datalake_google_ads_clean.geo_target_constant AS gt_region
    ON aggregated.geo_target_region = gt_region.resource_name;