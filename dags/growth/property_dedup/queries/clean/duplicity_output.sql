SELECT
  id,
  similar_property_id AS id_similar_property,
  action_type,
  duplicity_reason,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_property_dedup_raw.duplicity_output