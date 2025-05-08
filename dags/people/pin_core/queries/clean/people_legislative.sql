SELECT
  person_id AS id_person,
  person_legislative_id AS id_person_legislative,
  business_group_id AS id_business_group,
  created_by,
  last_updated_by AS updated_by,
  legislation_code,
  marital_status,
  sex,
  highest_education_level,
  TO_DATE(marital_status_date) AS dt_marital_status,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_people_legislative_f
