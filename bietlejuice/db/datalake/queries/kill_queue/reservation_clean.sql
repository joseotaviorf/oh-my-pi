SELECT
  cast(r.id as bigint) as id,
  cast(r.created_at as timestamp) as created_at,
  cast(r.updated_at as timestamp) as updated_at,
  cast(r.version as integer) as version,
  cast(r.attempt as integer) as attempt,
  cast(r.rent_flow_id as bigint) as rent_flow_id,
  r.status,
  cast(r.tenant_id as bigint) as tenant_id,
  cast(r.value as decimal(19,2)) as value,
  cast(h.main_id as bigint) as house_id,
  r.mundipagg_token,
  cast(r.is_ongoing as integer) as is_ongoing
FROM datalake_clean.killqueue_reservation r
left join datalake_clean.killqueue_house h on r.house_id = h.id;