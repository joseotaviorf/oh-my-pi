SELECT
  business_group_id AS id_business_group,
  person_id AS id_person,
  phone_id AS id_phone,
  created_by,
  last_updated_by AS updated_by,
  legislation_code,
  phone_type,
  phone_number,
  area_code,
  country_code_number,
  search_phone_number,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(date_from) AS dt_started,
  TO_DATE(date_to) AS dt_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_phones
