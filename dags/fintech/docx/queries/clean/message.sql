SELECT
  id AS id_message,
  incremental_id AS id_incremental,
  destination,
  headers,
  payload,
  published AS is_published,
  TO_TIMESTAMP(creation_time / 1000) AS ts_created
FROM
  datalake_docx_raw.message
