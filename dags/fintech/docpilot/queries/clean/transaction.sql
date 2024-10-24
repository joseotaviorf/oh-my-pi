SELECT
  id,
  remote_addr,
  issued_at AS ts_issued
FROM
    datalake_docpilot_raw.transaction
