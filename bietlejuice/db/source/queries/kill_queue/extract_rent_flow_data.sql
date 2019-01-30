SELECT
  id,
  cast(created_at as char) as created_at,
  cast(updated_at as char) as updated_at,
  version,
  firestore_id,
  cast(house_id as char) as house_id,
  cast(tenant_id as char) as tenant_id,
  status
FROM rent_flow;