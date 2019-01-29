SELECT
  id,
  created_at,
  updated_at,
  version,
  attempt,
  rent_flow_id,
  status,
  tenant_id,
  value,
  house_id,
  mundipagg_token,
  cast(is_ongoing as CHAR) as is_ongoing
FROM reservation;