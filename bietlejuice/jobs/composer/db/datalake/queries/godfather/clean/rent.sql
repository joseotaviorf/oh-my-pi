SELECT
  id,
  main_id as id_main,
  house_id as id_house,
  tenant_id as id_tenant,
  version,
  main_created_at as ts_main_created,
  main_updated_at as ts_main_updated,
  created_at as ts_created,
  updated_at as ts_updated
FROM datalake_godfather_raw.rent
