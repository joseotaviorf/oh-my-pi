SELECT
  id,
  property_id AS id_property,
  owner_id AS id_owner,
  external_id AS id_external,
  owner_uuid AS uuid_owner,
  address,
  context_ownership,
  context_property_status,
  similarity_score,
  is_same_property_owner,
  property_updated_at AS ts_property_updated,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_property_dedup_raw.similar_property