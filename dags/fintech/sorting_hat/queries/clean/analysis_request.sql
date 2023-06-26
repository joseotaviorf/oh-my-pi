SELECT
  id,
  external_id as id_external,
  business_context,
  enterprise_group,
  external_source,
  result,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysisrequest