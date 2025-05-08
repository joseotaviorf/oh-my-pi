SELECT
  assignment_status_type_id AS id_assignment_status_type,
  business_group_id AS id_business_group,
  created_by,
  last_updated_by AS updated_by,
  language,
  source_lang AS source_language,
  seed_data_source,
  user_status,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_assignment_status_types_tl
