SELECT
  person_id AS id_person,
  business_group_id AS id_business_group,
  category_code,
  correspondence_language,
  created_by,
  last_updated_by AS updated_by,
  user_guid,
  country_of_birth,
  region_of_birth,
  town_of_birth,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(date_of_birth) AS dt_of_birth,
  TO_DATE(date_of_death) AS date_of_death,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_persons
