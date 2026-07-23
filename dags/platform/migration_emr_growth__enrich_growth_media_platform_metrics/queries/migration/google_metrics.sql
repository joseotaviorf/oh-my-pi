WITH aggregated_google_report AS (
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
    (
      cost / 1000000
    ) AS total_cost,
    dt_loaded AS dt_cost
  FROM datalake_google_ads_clean.ad_group_geo_performance
  WHERE
    CAST(dt_loaded AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND (
      clicks > 0 OR impressions > 0 OR cost > 0
    )
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
    (
      cost / 1000000
    ) AS total_cost,
    dt_loaded AS dt_cost
  FROM datalake_google_ads_clean.campaigns_geo_performance
  WHERE
    CAST(dt_loaded AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND (
      clicks > 0 OR impressions > 0 OR cost > 0
    )
    AND NOT id_campaign IN (
      SELECT DISTINCT
        id_campaign
      FROM datalake_google_ads_clean.ad_group_geo_performance
      WHERE
        CAST(dt_loaded AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    )
)
SELECT
  aggregated.id_account, /* Dimensions */
  aggregated.id_campaign,
  aggregated.id_adset,
  CAST(NULL AS STRING) AS id_ad,
  aggregated.account_snake_case AS account_name,
  'google' AS origin,
  report_type,
  aggregated.utm_campaign,
  aggregated.utm_term,
  CAST(NULL AS STRING) AS utm_content,
  aggregated.country_code, /* Regions */
  CASE
    WHEN (
      gt_region.name = 'Federal District'
    )
    THEN 'Distrito Federal'
    ELSE REGEXP_REPLACE(gt_region.name, '\\^State of ', '')
  END AS state,
  gt_city.name AS city,
  aggregated.clicks, /* Metrics */
  aggregated.conversions AS conversions,
  aggregated.impressions,
  aggregated.total_cost,
  aggregated.dt_cost, /* Date Reference */
  YEAR(TO_DATE(aggregated.dt_cost)) AS year,
  MONTH(TO_DATE(aggregated.dt_cost)) AS month,
  DAY(TO_DATE(aggregated.dt_cost)) AS day
FROM aggregated_google_report AS aggregated
LEFT JOIN datalake_google_ads_clean.geo_target_constant AS gt_city
  ON aggregated.geo_target_city = gt_city.resource_name
LEFT JOIN datalake_google_ads_clean.geo_target_constant AS gt_region
  ON aggregated.geo_target_region = gt_region.resource_name