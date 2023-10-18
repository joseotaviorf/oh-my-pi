SELECT
  id,
  track_id AS id_track,
  file_storage_key,
  document_type,
  status,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_trato_feito_raw.evictions_report