SELECT
  id as sk_partner,
  id as id_partner,
  name,
  trade_name,
  phone,
  email,
  cnpj,
  creci,
  type,
  ts_partnership_started,
  ts_created,
  ts_updated,
  now() as ts_load
FROM datalake_ebdb_clean.partner