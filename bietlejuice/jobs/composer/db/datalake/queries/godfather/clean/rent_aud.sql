SELECT
  id,
  house_id as id_house,
  tenant_id as id_tenant,
  rev,
  revtype as rev_type,
  main_created_at as ts_main_created,
  main_updated_at as ts_main_updated
FROM
  datalake_godfather_raw.rent_aud
