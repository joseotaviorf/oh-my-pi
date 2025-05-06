SELECT
  business_group_id AS id_business_group,
  person_id AS id_person,
  email_address_id AS id_email_address,
  created_by,
  last_updated_by AS updated_by,
  email_address,
  email_type,
  CAST(object_version_number AS INT) AS object_version_number,
  mastered_in_ldap_flag = 'Y' AS has_mastered_in_ldap,
  TO_DATE(date_from) AS dt_started,
  TO_DATE(date_to) AS dt_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_email_addresses
