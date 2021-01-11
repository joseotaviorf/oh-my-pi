SELECT
  id_reservation as sk_reservation,
  id_reservation,
  version,
  attempt,
  status,
  cancellation_reason,
  value,
  installments,
  is_ongoing,
  ts_created,
  ts_updated,
  now() as ts_load
FROM datalake_kill_queue.reservation
