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
  id_advertiser AS id_account, /* Dimensions */
  id_campaign,
  id_ad_set AS id_adset,
  CAST(NULL AS STRING) AS id_ad,
  CASE
    WHEN advertiser_name = 'Quinto Andar Demand RetenÃ§Ã£o - ForSale BR'
    THEN 'Quinto Andar Demand Retenção - ForSale BR'
    ELSE advertiser_name
  END AS account_name,
  'criteo' AS origin,
  'campaigns' AS report_type,
  campaign_name AS utm_campaign,
  ad_set AS utm_term,
  CAST(NULL AS STRING) AS utm_content,
  'BR' AS country_code, /* Regions */
  cc.region AS state,
  lk.locality AS city,
  cc.clicks, /* Metrics */
  CAST(NULL AS BIGINT) AS conversions,
  cc.displays AS impressions,
  cc.cost AS total_cost,
  cc.dt_report AS dt_cost, /* Date Reference */
  YEAR(TO_DATE(cc.dt_report)) AS year,
  MONTH(TO_DATE(cc.dt_report)) AS month,
  DAY(TO_DATE(cc.dt_report)) AS day
FROM datalake_criteo.criteo_campaigns AS cc
LEFT JOIN lookup AS lk
  ON cc.zip_code BETWEEN lk.start_range AND lk.end_range
WHERE
  CAST(dt_report AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
