SELECT
  business_group_id AS id_business_group,
  dashboard_tmpl_id AS id_dashboard_template,
  name,
  language,
  source_lang AS source_language,
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
  datalake_pin_hr_review_raw.hrr_dashboard_tmpls_tl