SELECT
  id,
  kind,
  POSITION,
  slug,
  visibility_mask,
  created_at AS ts_created,
  updated_at AS ts_updated,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_raw.offer_variables