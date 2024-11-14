SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renaming
  CAST(id AS INT) AS sk_visit,
  CAST(id  AS INT) AS id_visit,
  code AS cd_visit,
  sv.business_unit,
  dt_visit AS day_visit,
  slot,
  slot_count,
  type,
  status,
  booking_type,
  ts_created AS dt_created,
  ts_updated AS dt_updated,
  NOW() AS ts_load
FROM
  datalake_ebdb_clean.visit AS v
LEFT JOIN
  datalake_sale_visit_hubs.sale_visit_hubs AS sv
    ON sv.id_booking = CAST(id AS INT)
