SELECT
  business_group_id AS id_business_group,
  category_id AS id_category,
  question_id AS id_question,
  response_type_id AS id_response_type,
  created_by,
  last_updated_by AS updated_by,
  status,
  question_code,
  question_type,
  latest_version = 'Y' AS is_latest_version,
  scored_flag = 'Y' AS is_scored,
  CAST(object_version_number AS INT) AS object_version_number,
  CAST(qstn_version_num AS INT) AS question_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_questions_b
