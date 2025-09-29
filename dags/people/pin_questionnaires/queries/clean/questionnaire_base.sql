SELECT
  questionnaire_id AS id_questionnaire,
  business_group_id AS id_business_group,
  questionnaire_code,
  CASE
    WHEN status = 'A' THEN 'active'
    WHEN status = 'I' THEN 'inactive'
    WHEN status = 'D' THEN 'draft'
    ELSE status
  END AS status,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  CAST(qstnr_version_num AS INT) AS questionnaire_version_number,
  in_use = 'Y' AS is_in_use,
  latest_version = 'Y' AS is_latest_version,
  privacy_flag = 'Y' AS is_privacy,
  scored_flag = 'Y' AS is_scored,
  template_flag = 'Y' AS is_template,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_questionnaires_raw.hrq_questionnaires_b
