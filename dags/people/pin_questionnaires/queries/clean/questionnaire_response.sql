SELECT
  business_group_id AS id_business_group,
  qstnr_participant_id AS id_questionnaire_participant,
  qstnr_response_id AS id_questionnaire_response,
  status,
  created_by,
  last_updated_by AS updated_by,
  latest_attempt_flag = 'Y' AS is_latest_attempt,
  CAST(object_version_number AS INT) AS object_version_number,
  total_score,
  CAST(attempt_num AS INT) AS attempt_number,
  CAST(qstnr_version_num AS INT) AS questionnaire_version_number,
  TO_DATE(submitted_date_time) AS dt_submitted,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_qstnr_responses
