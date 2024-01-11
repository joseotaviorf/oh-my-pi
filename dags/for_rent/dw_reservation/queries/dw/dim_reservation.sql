SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  id_reservation AS sk_reservation,
  id_reservation,
  version,
  attempt,
  status,
  cancellation_reason,
  CAST(value AS DECIMAL(19,2)) AS value,
  installments,
  CAST(is_ongoing AS INTEGER) AS is_ongoing,
  ts_created,
  ts_updated
FROM
  datalake_kill_queue.reservation
