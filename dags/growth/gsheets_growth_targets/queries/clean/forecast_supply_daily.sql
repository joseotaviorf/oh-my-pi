SELECT
  NULLIF(business, '') AS business,
  NULLIF(year_month, '') AS year_month,
  NULLIF(region, '') AS region,
  NULLIF(planning_conversion, '') AS planning_conversion,
  NULLIF(planning_operation, '') AS planning_operation,
  NULLIF(planning_cluster_adj, '') AS planning_cluster_adj,
  NULLIF(company_report_origin, '') AS company_report_origin,
  CAST(REPLACE(NULLIF(p, ''), ',', '') AS FLOAT) AS prospects,
  CAST(REPLACE(NULLIF(q, ''), ',', '') AS FLOAT) AS qualifieds,
  CAST(REPLACE(NULLIF(aq, ''), ',', '') AS FLOAT) AS available_qualifieds,
  CAST(REPLACE(NULLIF(o, ''), ',', '') AS FLOAT) AS opportunities,
  CAST(REPLACE(NULLIF(fl, ''), ',', '') AS FLOAT) AS first_listings,
  CAST(NULLIF(date, '') AS DATE) AS date
FROM
  datalake_gsheets_raw.forecast_supply_daily