SELECT
  id,
  guarantee_id AS id_guarantee,
  sap_id AS id_sap,
  idempotency_id AS id_idempotency,
  hash,
  status,
  request,
  event_date,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_rental_guarantee_raw.invoice
