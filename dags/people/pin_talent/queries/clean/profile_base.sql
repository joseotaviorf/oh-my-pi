SELECT
  business_group_id AS id_business_group,
  person_id AS id_person,
  profile_id AS id_profile,
  profile_type_id AS id_profile_type,
  party_id AS id_party,
  profile_code,
  profile_status_code,
  profile_usage_code,
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
  datalake_pin_talent_raw.hrt_profiles_b
