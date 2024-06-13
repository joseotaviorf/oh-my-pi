SELECT
  NULLIF(week_start, '') AS week_start,
  NULLIF(city_group, '') AS city_group,
  NULLIF(month_start, '') AS month_start,
  NULLIF(ciq_type, '') AS ciq_type,
  'SALE' AS nm_business_context,
  CAST(REPLACE(NULLIF(fl, ''), ',', '') AS FLOAT) AS first_listings,
  CAST(NULLIF(date, '') AS DATE) AS date
FROM
  datalake_gsheets_raw.sale_ciq_target