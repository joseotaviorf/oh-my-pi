WITH facebook AS (
  SELECT
    'facebook' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_start) AS dt_start
  FROM datalake_growth_facebook_insights.facebook_insights_region
  WHERE
    CAST(dt_start AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY ALL
), criteo AS (
  SELECT
    'criteo' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_report) AS dt_start
  FROM datalake_criteo.criteo_campaigns
  WHERE
    CAST(dt_report AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY ALL
), trovit AS (
  SELECT
    'trovit' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_attribution) AS dt_start
  FROM datalake_lifull_campaigns_clean.trovit_campaigns
  WHERE
    CAST(dt_attribution AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY ALL
), google AS (
  SELECT
    'google' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_loaded) AS dt_start
  FROM datalake_google_ads_clean.ad_group_geo_performance
  WHERE
    CAST(dt_created AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY ALL
  UNION ALL
  SELECT
    'google' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_loaded) AS dt_start
  FROM datalake_google_ads_clean.campaigns_geo_performance
  WHERE
    CAST(dt_created AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY ALL
), base AS (
  SELECT
    *
  FROM google
  UNION ALL
  SELECT
    *
  FROM facebook
  UNION ALL
  SELECT
    *
  FROM criteo
  UNION ALL
  SELECT
    *
  FROM trovit
), base_deduplicated AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY origin, id_campaign ORDER BY dt_start DESC) AS _w
    FROM base
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  id_campaign AS merge_key,
  id_campaign,
  campaign_name,
  origin,
  CAST(TRUE AS BOOLEAN) AS is_current,
  dt_start,
  CAST(NULL AS DATE) AS dt_end
FROM base_deduplicated
UNION ALL
SELECT
  NULL AS merge_key,
  b.id_campaign,
  b.campaign_name,
  b.origin,
  CAST(TRUE AS BOOLEAN) AS is_current,
  b.dt_start,
  CAST(NULL AS DATE) AS dt_end
FROM base_deduplicated AS b
LEFT JOIN datalake_growth_media_platform.campaign_name_history AS cn
  ON b.id_campaign = cn.id_campaign
  AND b.campaign_name = cn.campaign_name
  AND b.origin = cn.origin
WHERE
  cn.id_campaign IS NULL
