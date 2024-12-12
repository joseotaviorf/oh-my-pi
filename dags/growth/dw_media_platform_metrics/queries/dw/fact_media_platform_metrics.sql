SELECT
  id_campaign AS sk_campaign,
  id_adset AS sk_adset,
  id_ad AS sk_ad, 
  id_region AS sk_region,
  BIGINT(DATE_FORMAT(dt_cost, 'yyyyMMdd')) AS sk_cost_date,
  name_convention_suffix,
  origin,
  country_code,
  utm_campaign,
  utm_term,
  utm_content,
  clicks,
  conversions,
  impressions,
  total_cost,
  dt_cost,
  year,
  month,
  day,
  NOW() AS ts_load
FROM 
  datalake_growth_media_platform.consolidated_metrics
WHERE 
    dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE