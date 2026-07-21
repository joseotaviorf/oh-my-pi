SELECT
  person_id AS id_person,
  business_group_id AS id_business_group,
  religion_id AS id_religion,
  created_by,
  last_updated_by AS updated_by,
  religion AS religion_code,
  legislation_code,
  CAST(object_version_number AS INT) AS object_version_number,
  primary_flag = 'Y' AS is_primary,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_religions
