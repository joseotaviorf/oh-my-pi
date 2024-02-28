SELECT
  id,
  machine_id as id_machine,
  group_name,
  group_type,
  result,
  status,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysisstategroup