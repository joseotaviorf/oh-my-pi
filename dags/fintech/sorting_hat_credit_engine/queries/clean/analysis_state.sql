SELECT
  id,
  state_group_id as id_state_group,
  subject_id as id_subject,
  input,
  raw_input,
  result,
  status,
  subject_type,
  structured_result,
  CAST(GET_JSON_OBJECT(structured_result, '$.homogeneous_group') AS STRING) AS homogeneous_group,
  CAST(GET_JSON_OBJECT(structured_result, '$.declared_income') AS DECIMAL) AS declared_income,
  CAST(GET_JSON_OBJECT(structured_result, '$.bureau_income') AS DECIMAL) AS bureau_income,
  CAST(GET_JSON_OBJECT(structured_result, '$.income_changes') AS DECIMAL) AS income_changes,
  CAST(GET_JSON_OBJECT(structured_result, '$.max_bureau_income') AS DECIMAL) AS max_bureau_income,
  CAST(GET_JSON_OBJECT(structured_result, '$.bureau_and_declared_ratio') AS DECIMAL) AS bureau_and_declared_ratio,
  CAST(GET_JSON_OBJECT(structured_result, '$.is_demoted_group') AS BOOLEAN) AS is_demoted_group,
  CAST(GET_JSON_OBJECT(structured_result, '$.elected_income') AS DECIMAL) AS elected_income,
  CAST(GET_JSON_OBJECT(structured_result, '$.is_retenant') AS BOOLEAN) AS is_retenant,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysisstate
