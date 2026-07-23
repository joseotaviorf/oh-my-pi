SELECT
  id_account, /* Dimensions */
  id_campaign,
  CAST(NULL AS STRING) AS id_adset,
  CAST(NULL AS STRING) AS id_ad,
  account_name,
  'trovit' AS origin,
  'trovit_campaigns' AS report_type,
  REGEXP_REPLACE(campaign_name, '\t', '') AS utm_campaign,
  CAST(NULL AS STRING) AS utm_term,
  CAST(NULL AS STRING) AS utm_content,
  country_code, /* Regions */
  CAST(NULL AS STRING) AS state,
  CAST(NULL AS STRING) AS city, /* not available in the table */
  clicks, /* Metrics */
  CAST(NULL AS BIGINT) AS conversions,
  CAST(NULL AS BIGINT) AS impressions,
  total_cost,
  dt_attribution AS dt_cost, /* Date Reference */
  YEAR(TO_DATE(dt_cost)) AS year,
  MONTH(TO_DATE(dt_cost)) AS month,
  DAY(TO_DATE(dt_cost)) AS day
FROM datalake_lifull_campaigns_clean.trovit_campaigns
WHERE
  CAST(dt_attribution AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)