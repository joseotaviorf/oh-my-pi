SELECT
  id,
  main_id as id_main,
  rent_flow_id as id_rent_flow,
  version,
  `status`,
  contract_type,
  tenant_signed as has_tenant_signed,
  owner_signed as has_owner_signed,
  partner_signed as has_partner_signed,
  main_created_at as ts_main_created,
  main_updated_at as ts_main_updated,
  tenant_signed_at as ts_tenant_signed,
  partner_signed_at as ts_partner_signed,
  owner_signed_at as ts_owner_signed,
  created_at as ts_created,
  updated_at as ts_updated
FROM
  datalake_godfather_raw.contract
