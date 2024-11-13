SELECT
  MD5(CONCAT(CAST(id_date AS STRING), '_', id_rule)) AS bk_sharing_rules,
  id_rule AS rule_code,
  country_code, 
  city_group,
  share,
  funnel_side,
  business_context,
  utm_campaign_modified,
  TO_DATE(CAST(id_date AS STRING), 'yyyyMMdd') AS dt_rule_costs,
  NOW() AS ts_load
FROM 
  datalake_growth_costs_sharing_rules.sharing_rules