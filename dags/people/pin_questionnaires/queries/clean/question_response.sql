SELECT
  business_group_id AS id_business_group,
  qstnr_question_id AS id_questionnaire_question,
  qstnr_response_id AS id_questionnaire_response,
  qstn_response_id AS id_question_response,
  qstn_answer_id AS id_question_answer,
  created_by,
  last_updated_by AS updated_by,
  answer_clob AS free_text_answer_unlimited,
  answer_text AS free_text_answer,
  answer_list AS multiple_choice_answer_list,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_qstn_responses
