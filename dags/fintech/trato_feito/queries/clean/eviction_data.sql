SELECT
  id,
  external_id AS id_external,
  context,
  cpf_client,
  distributor_code_external,
  occurrence_code_external,
  has_occurrence_problem_external,
  occurrence_due_date_external AS dt_occurrence_due_date_external,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_trato_feito_raw.eviction_data
