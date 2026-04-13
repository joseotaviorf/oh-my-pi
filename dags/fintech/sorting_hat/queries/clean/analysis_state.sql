WITH json_parsed AS (
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
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    FROM_JSON(
      structured_result,
      'homogeneous_group STRING, declared_income DECIMAL(18,2), bureau_income DECIMAL(18,2), income_changes DECIMAL(18,2), max_bureau_income DECIMAL(18,2), bureau_and_declared_ratio DECIMAL(18,2), is_demoted_group BOOLEAN, elected_income DECIMAL(18,2), is_retenant BOOLEAN'
    ) AS parsed_json
  FROM
    datalake_sorting_hat_raw.analysisstate
)

SELECT
  id,
  id_state_group,
  id_subject,
  input,
  raw_input,
  result,
  status,
  subject_type,
  structured_result,
  parsed_json.homogeneous_group,
  parsed_json.declared_income,
  parsed_json.bureau_income,
  parsed_json.income_changes,
  parsed_json.max_bureau_income,
  parsed_json.bureau_and_declared_ratio,
  parsed_json.is_demoted_group,
  parsed_json.elected_income,
  parsed_json.is_retenant,
  ts_created,
  ts_updated
FROM
  json_parsed
