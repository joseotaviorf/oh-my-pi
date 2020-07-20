SELECT
  id as sk_visit,
  id as id_visit,
  code as code_visit,
  dt_visit,
  slot,
  slot_count,
  type,
  status,
  booking_type,
  ts_created,
  ts_updated,
  now() as ts_load
FROM
  datalake_ebdb_clean.visit
