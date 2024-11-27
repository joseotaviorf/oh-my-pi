WITH facebook AS (
  SELECT
    'facebook' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_start) AS dt_start
  FROM 
    datalake_facebook_insights_clean.facebook_insights
  WHERE 
    DATE(dt_start) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
),
criteo AS (
  SELECT
    'criteo' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_report) AS dt_start
  FROM 
    datalake_criteo.criteo_campaigns
  WHERE 
    DATE(dt_report) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
),
mitula AS (
  SELECT
    'mitula' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_attribution) AS dt_start
  FROM 
    datalake_lifull_campaigns_clean.mitula_campaigns
  WHERE 
    DATE(dt_attribution) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
),
rtb AS (
  SELECT
    'rtb' AS origin,
    id_sub_campaign AS id_campaign,
    sub_campaign_name AS campaign_name,
    MIN(dt_attribution) AS dt_start
  FROM 
    datalake_rtb_campaigns_clean.rtb_campaigns
  WHERE 
    DATE(dt_attribution) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
),
trovit AS (
  SELECT
    'trovit' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_attribution) AS dt_start
  FROM 
    datalake_lifull_campaigns_clean.trovit_campaigns
  WHERE 
    DATE(dt_attribution) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
),
google AS (
  SELECT 
    'google' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_loaded) AS dt_start
  FROM 
    datalake_google_ads_clean.ads_performance
  WHERE 
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL 
  UNION ALL
  SELECT 
    'google' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_loaded) AS dt_start
  FROM 
    datalake_google_ads_clean.keywords_performance
  WHERE 
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL 
  UNION ALL
  SELECT 
    'google' AS origin,
    id_campaign,
    campaign_name,
    MIN(dt_loaded) AS dt_start
  FROM 
    datalake_google_ads_clean.campaigns_performance
  WHERE 
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL 
  UNION ALL
  SELECT 
      'google' AS origin,
      id_campaign,
      campaign_name,
      MIN(dt_loaded) AS dt_start
  FROM 
    datalake_google_ads_clean.videos_performance
  WHERE 
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
),
base AS (
  SELECT * FROM google
  UNION ALL
  SELECT * FROM facebook
  UNION ALL
  SELECT * FROM criteo
  UNION ALL
  SELECT * FROM mitula
  UNION ALL
  SELECT * FROM trovit
  UNION ALL
  SELECT * FROM rtb
),
base_deduplicated AS (
  SELECT 
    *
  FROM base
  QUALIFY ROW_NUMBER() OVER (PARTITION BY origin, id_campaign ORDER BY dt_start DESC) = 1
)
SELECT 
  id_campaign AS merge_key,
  id_campaign,
  campaign_name,
  origin,
  TRUE::BOOLEAN AS is_current,
  dt_start,
  NULL::DATE AS dt_end
FROM base_deduplicated
UNION ALL
SELECT 
  NULL AS merge_key,
  b.id_campaign,
  b.campaign_name,
  b.origin,
  TRUE::BOOLEAN AS is_current,
  b.dt_start,
  NULL::DATE AS dt_end
FROM 
  base_deduplicated b
  LEFT JOIN 
    datalake_growth_media_platform.campaign_name_history cn 
      ON b.id_campaign = cn.id_campaign
      AND b.campaign_name = cn.campaign_name
      AND b.origin = cn.origin
WHERE cn.id_campaign IS NULL
