SELECT
  questionnaire_id AS id_questionnaire,
  business_group_id AS id_business_group,
  name,
  description,
  REGEXP_REPLACE(intro_text, '<[^>]+>|&nbsp;', '') AS intro_text,
  language,
  source_lang AS source_language,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  CAST(qstnr_version_num AS INT) AS questionnaire_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_questionnaires_tl
