SELECT
  business_group_id AS id_business_group,
  qstn_answer_id AS id_question_answer,
  long_text,
  language,
  source_lang AS source_language,
  response_feedback,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_qstn_answers_tl
