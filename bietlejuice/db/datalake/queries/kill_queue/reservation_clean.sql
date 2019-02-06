SELECT
  cast(id as bigint) as id,
  cast(created_at as timestamp) as created_at,
  cast(updated_at as timestamp) as updated_at,
  cast(version as integer) as version,
  cast(attempt as integer) as attempt,
  cast(rent_flow_id as bigint) as rent_flow_id,
  status,
  cast(tenant_id as bigint) as tenant_id,
  cast(value as decimal(19,2)) as value,
  cast(house_id as bigint) as house_id,
  mundipagg_token,
  cast(is_ongoing as integer) as is_ongoing
FROM datalake_clean.killqueue_reservation;