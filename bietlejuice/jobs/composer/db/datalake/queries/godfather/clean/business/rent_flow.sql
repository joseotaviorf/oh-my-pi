SELECT
  id,
  rent_id as id_rent,
  version,
  `status`,
  created_at as ts_created,
  updated_at as ts_updated
FROM datalake_godfather_raw.business_rent_flow
