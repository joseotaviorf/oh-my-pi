SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  id_reservation as sk_reservation,
  id_reservation,
  version,
  attempt,
  status,
  cancellation_reason,
  value,
  installments,
  cast(is_ongoing as integer) as is_ongoing,
  ts_created,
  ts_updated
FROM datalake_kill_queue.reservation
