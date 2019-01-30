SELECT
  cast(id as char) as id,
  cast(created_at as char) as created_at,
  cast(updated_at as char) as updated_at,
  cast(version as char) as version,
  cast(attempt as char) as attempt,
  cast(rent_flow_id as char) as rent_flow_id,
  status,
  cast(tenant_id as char) as tenant_id,
  cast(value as char) as value,
  cast(house_id as char) as house_id,
  mundipagg_token,
  cast(coalesce(is_ongoing, 0) as unsigned) as is_ongoing
FROM reservation;