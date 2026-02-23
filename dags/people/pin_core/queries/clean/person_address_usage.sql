SELECT
  person_addr_usage_id AS id_person_address_usage,
  person_id AS id_person,
  business_group_id AS id_business_group,
  address_id AS id_address,
  address_type,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_person_addr_usages_f
