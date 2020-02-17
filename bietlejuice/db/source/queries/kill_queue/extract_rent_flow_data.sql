SELECT
  id,
  cast(date(ts_created) as date) as created_at,
  cast(date(ts_updated) as date) as updated_at,
  version,
  id_firestore,
  id_house as house_id,
  id_tenant as tenant_id,
  status
FROM rent_flow;