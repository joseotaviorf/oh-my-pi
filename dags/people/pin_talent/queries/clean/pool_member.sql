SELECT
  pool_id AS id_pool,
  pool_member_id AS id_pool_member,
  enterprise_id AS id_enterprise,
  member_id AS id_member,
  created_by,
  last_updated_by AS updated_by,
  pool_member_type,
  source_code,
  status,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(member_since) AS dt_member_since,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_talent_raw.hrt_pool_members
