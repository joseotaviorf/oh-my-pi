SELECT
  business_group_id AS id_business_group,
  section_id AS id_section,
  language,
  source_lang AS source_language,
  created_by,
  last_updated_by AS updated_by,
  name AS section_name,
  description AS section_description,
  seed_data_source,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_talent_raw.hrt_profile_typ_sections_tl
