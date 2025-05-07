SELECT
  business_group_id AS id_business_group,
  content_type_id AS id_content_type,
  profile_id AS id_profile,
  profile_section_id AS id_profile_section,
  section_id AS id_section,
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
  datalake_pin_talent_raw.hrt_profile_sections_b
