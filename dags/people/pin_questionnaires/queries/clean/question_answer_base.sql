SELECT
  business_group_id AS id_business_group,
  qstn_answer_id AS id_question_answer,
  question_id AS id_question,
  created_by,
  last_updated_by AS updated_by,
  answer_code,
  CAST(object_version_number AS INT) AS object_version_number,
  CAST(qstn_version_num AS INT) AS question_version_number,
  CAST(seq_num AS INT) AS sequence_number,
  score,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_qstn_answers_b
