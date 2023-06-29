SELECT 
  NULLIF(cost_origin, '') AS mkt_origin,
  NULLIF(city_group, '') AS city_group,
  NULLIF(cost_type, '') AS source,
  CAST(NULLIF(cost, '') AS FLOAT) AS cost,
  CAST(NULLIF(has_real_cost, '') AS BOOLEAN) AS has_real_cost,
  DATE(date) AS dt_created
FROM
  datalake_gsheets_raw.provisioned_costs_import
