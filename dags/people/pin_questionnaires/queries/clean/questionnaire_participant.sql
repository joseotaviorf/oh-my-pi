SELECT
  business_group_id AS id_business_group,
  participant_id AS id_participant,
  qstnr_participant_id AS id_questionnaire_participant,
  questionnaire_id AS id_questionnaire,
  subject_id AS id_subject,
  subscriber_id AS id_subscriber,
  created_by,
  last_updated_by AS updated_by,
  status,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_qstnr_participants
