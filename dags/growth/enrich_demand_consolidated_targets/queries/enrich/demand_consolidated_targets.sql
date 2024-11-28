-- Target de New Prospects de Rent
SELECT
  'prospects' AS metric_name, 
  'new' AS submetric_name, 
  'Rent' AS business_context,
  t.funnel_side, 
  'Rent' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium,
  NULL::STRING AS source,
  t.operation_channel, 
  t.referral_type,
  'BR' AS country_code, 
  t.city_group, 
  t.date AS dt_target,
  SUM(t.ntp) AS target
FROM datalake_gsheets_clean.rental_prospect_target AS t
GROUP BY ALL

UNION ALL 

-- Target de Recovered Prospects de Rent
SELECT
  'prospects' AS metric_name, 
  'recovered' AS submetric_name, 
  'Rent' AS business_context,
  t.funnel_side, 
  'Rent' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium,
  NULL::STRING AS source,
  t.operation_channel, 
  t.referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.date AS dt_target,
  SUM(t.rtp) AS target
FROM datalake_gsheets_clean.rental_prospect_target AS t
GROUP BY ALL

UNION ALL 

-- Target de New Prospects de Sale
SELECT
  'prospects' AS metric_name, 
  'new' AS submetric_name, 
  'Sale' AS business_context,
  t.funnel_side, 
  'Sale' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium,
  NULL::STRING AS source,
  t.operation_channel, 
  t.referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.date AS dt_target,
  SUM(t.nbp) AS target
FROM datalake_gsheets_clean.sale_prospect_target AS t
GROUP BY ALL

UNION ALL 

-- Target de Recovered Prospects de Sale
SELECT
  'prospects' AS metric_name, 
  'recovered' AS submetric_name, 
  'Sale' AS business_context,
  t.funnel_side, 
  'Sale' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium,
  NULL::STRING AS source,
  t.operation_channel, 
  t.referral_type,
  'BR' AS country_code, 
  t.city_group, 
  t.date AS dt_target,
  SUM(t.rbp) AS target
FROM datalake_gsheets_clean.sale_prospect_target AS t
GROUP BY ALL

UNION ALL 

-- Target de Custos de Rent e Sale
SELECT 
  'marketing_cost' AS metric_name, 
  NULL AS submetric_name, 
  LOWER(business_context) AS business_context,
  t.funnel_side, 
  'Rent' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium,
  NULL::STRING AS source,
  NULL AS operation_channel, 
  NULL AS referral_type,
  'BR' AS country_code, 
  t.city_group, 
  t.date AS dt_target,
  SUM(t.cost) AS target
FROM datalake_gsheets_clean.mkt_cost_target AS t
GROUP BY ALL

UNION ALL 

-- Target de ToF Diário de Rent
SELECT DISTINCT
  'tof' AS metric_name, 
  'daily' AS submetric_name, 
  'Rent' AS business_context,
  t.funnel_side, 
  'Rent' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium, 
  NULL::STRING AS source,
  NULL AS operation_channel, 
  NULL AS referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.date AS dt_target,
  SUM(t.tof_users) AS target
FROM datalake_gsheets_clean.rental_tof_daily_target AS t
GROUP BY ALL

UNION ALL 

-- Target de ToF Diário de Sale
SELECT DISTINCT
  'tof' AS metric_name, 
  'daily' AS submetric_name, 
  'Rent' AS business_context,
  t.funnel_side, 
  'Rent' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium, 
  NULL::STRING AS source,
  NULL AS operation_channel, 
  NULL AS referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.date AS dt_target,
  SUM(t.tof_users) AS target
FROM datalake_gsheets_clean.sale_tof_daily_target AS t
GROUP BY ALL

UNION ALL 

-- Target de ToF Semanal de Rent
SELECT DISTINCT
  'tof' AS metric_name, 
  'weekly' AS submetric_name, 
  'Rent' AS business_context,
  t.funnel_side, 
  'Rent' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium, 
  NULL::STRING AS source,
  NULL AS operation_channel, 
  NULL AS referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.week_start AS dt_target, 
  SUM(t.tof_users) AS target
FROM datalake_gsheets_clean.rental_tof_weekly_target AS t
GROUP BY ALL

UNION ALL 

-- Target de ToF Semanal de Sale
SELECT DISTINCT
  'tof' AS metric_name, 
  'weekly' AS submetric_name, 
  'Sale' AS business_context,
  t.funnel_side, 
  'Sale' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium, 
  NULL::STRING AS source,
  NULL AS operation_channel, 
  NULL AS referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.week_start AS dt_target, 
  SUM(t.tof_users) AS target
FROM datalake_gsheets_clean.sale_tof_weekly_target AS t
GROUP BY ALL

UNION ALL 

-- Target de ToF Mensal de Rent
SELECT DISTINCT
  'tof' AS metric_name, 
  'monthly' AS submetric_name, 
  'Rent' AS business_context,
  t.funnel_side, 
  'Rent' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium, 
  NULL::STRING AS source,
  NULL AS operation_channel, 
  NULL AS referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.month_start AS dt_target, 
  SUM(t.tof_users) AS target
FROM datalake_gsheets_clean.rental_tof_monthly_target AS t
GROUP BY ALL

UNION ALL 

-- Target de ToF Mensal de Sale
SELECT DISTINCT
  'tof' AS metric_name, 
  'monthly' AS submetric_name, 
  'Sale' AS business_context,
  t.funnel_side, 
  'Sale' AS campaign_business_context, 
  t.campaign_strategy_intent, 
  t.behavior_type, 
  t.medium, 
  NULL::STRING AS source,
  NULL AS operation_channel, 
  NULL AS referral_type, 
  'BR' AS country_code, 
  t.city_group, 
  t.month_start AS dt_target, 
  SUM(t.tof_users) AS target
FROM datalake_gsheets_clean.sale_tof_monthly_target AS t
GROUP BY ALL