SELECT
  id,
  external_id AS id_external,
  context,
  law_firm,
  status,
  user_registered,
  status_recommendation,
  status_reason,
  snapshot,
  TIMESTAMP(status_updated_at) AS ts_status_updated,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_trato_feito_raw.eviction