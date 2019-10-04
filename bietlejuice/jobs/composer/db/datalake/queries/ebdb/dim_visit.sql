SELECT
  id_visit AS sk_visit,
  id_visit,
  cd_visit,
  dt_visit,
  slot,
  slot_count,
  type,
  status,
  booking_type,
  ts_created,
  ts_updated
FROM
  datalake_ebdb_clean.visit
