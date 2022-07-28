SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  cast(id as int) as sk_visit,
  cast(id  as int) as id_visit,
  code as cd_visit,
  dt_visit as day_visit,
  slot,
  slot_count,
  type,
  status,
  booking_type,
  ts_created as dt_created,
  ts_updated as dt_updated,
  now() as dt_timestamp
FROM
  datalake_ebdb_clean.visit
