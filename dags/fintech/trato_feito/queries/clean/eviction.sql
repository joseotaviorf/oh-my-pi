SELECT
  id,
  external_id AS id_external,
  context,
  law_firm,
  status,
  sub_status,
  user_registered,
  status_recommendation,
  status_reason,
  snapshot,
  external_metadata,
  distribution_date AS dt_distribution,
  TIMESTAMP(status_updated_at) AS ts_status_updated,
  TIMESTAMP(sub_status_updated_at) AS ts_sub_status_updated,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_trato_feito_raw.eviction
