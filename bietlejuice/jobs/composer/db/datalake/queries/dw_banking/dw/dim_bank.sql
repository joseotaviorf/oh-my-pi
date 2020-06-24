select
  id as sk_bank,
  id as id_bank,
  code,
  name,
  febraban_name,
  featured_rank,
  ts_created,
  ts_updated,
  now() as ts_load
from datalake_ebdb_clean.bank
