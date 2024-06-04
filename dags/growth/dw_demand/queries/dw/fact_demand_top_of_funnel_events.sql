SELECT
  id_top_of_funnel_event AS sk_tof_event,
  id_tof_user AS sk_tof_user,
  id_house AS sk_house,
  CAST(sk_region AS INTEGER) AS sk_region,
  naming_convention_sufix,
  business_context,
  entrance_uri,
  referrer,
  app_type,
  origin,
  operation_channel,
  platform,
  utm_source,
  utm_medium,
  branded,
  utm_campaign,
  utm_content,
  utm_term,
  behavior_type,
  campaign_business_context,
  campaign_strategy_intent,
  campaign_landing_page,
  funnel_side,
  medium,
  source,
  CASE WHEN h.internal_admin_info LIKE '%[3P-%]%' THEN TRUE ELSE FALSE END AS is_rede_demand,
  dt_event,
  ts_event,
  year,
  month,
  day,
  NOW() AS ts_load
FROM
  datalake_demand_flows.top_of_funnel_results tofr 
LEFT JOIN datalake_ebdb_clean.house AS h 
    ON h.id = tofr.id_house
WHERE 
    DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}') 