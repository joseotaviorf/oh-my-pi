SELECT
  cast(r.id as bigint) as id_reservation,
  id_rent_flow,
  r.id_tenant,
  h.id_main as id_house,
  cast(r.version as integer) as version,
  cast(r.attempt as integer) as attempt,
  r.status,
  r.value,
  r.mundipagg_token,
  r.cancellation_reason,
  r.installments,
  cast(cast(r.is_ongoing as integer) as boolean) as is_ongoing,
  r.ts_created,
  r.ts_updated
FROM datalake_kill_queue_clean.reservation r
LEFT JOIN datalake_kill_queue_clean.house h
    ON r.id_house = h.id
