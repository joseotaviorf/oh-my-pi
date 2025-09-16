SELECT
  id,
  parent_id AS id_parent,
  name,
  created_at AS ts_created,
  updated_at AS ts_updated,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_raw.departments