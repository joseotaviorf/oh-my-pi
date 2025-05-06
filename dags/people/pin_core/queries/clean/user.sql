SELECT
  user_id AS id_user,
  person_id AS id_person,
  business_group_id AS id_business_group,
  created_by,
  last_updated_by AS updated_by,
  multitenancy_username,
  username,
  user_data_checksum,
  user_distinguished_name,
  user_guid,
  active_flag = 'Y' AS is_active,
  suspended = 'Y' AS is_suspended,
  credentials_email_sent = 'Y' AS has_credentials_email_sent,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_users
