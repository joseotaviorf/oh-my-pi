SELECT
  id,
  id_plan,
  id_company,
  pricing,
  coverage,
  damage,
  commission,
  version,
  is_active,
  ts_created,
  ts_updated,
  NOW() AS ts_snapshot,
  YEAR(CURRENT_DATE()) AS year,
  MONTH(CURRENT_DATE()) AS month,
  DAY(CURRENT_DATE()) AS day
FROM
  datalake_rental_guarantee_platform_clean.company_plan
