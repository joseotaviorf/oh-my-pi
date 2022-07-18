SELECT
  db.id AS id_visit,
  u.email,
  tbr.visit_type,
  db.status,
  db.reason_category AS cancellation_reason_category,
  db.responsible,
  db.ts_booking_local_tz AS ts_visit,
  db.ts_created_local_tz AS ts_visit_scheduling,
  db.ts_first_canceled AS ts_visit_cancellation
FROM
  datalake_booking.booking AS db
LEFT JOIN datalake_booking.booking_review AS tbr
  ON tbr.id_booking = db.id
LEFT JOIN datalake_ebdb_clean.user AS u
  ON u.id = db.id_visitor
WHERE
    db.type = 'Visita'