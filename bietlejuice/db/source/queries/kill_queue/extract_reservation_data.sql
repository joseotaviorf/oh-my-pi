SELECT
  id,
  cast(date(ts_created) as date) as created_at,
  cast(date(ts_updated) as date) as updated_at,
  version,
  attempt,
  id_rent_flow as rent_flow_id,
  status,
  id_tenant as tenant_id,
  value,
  id_house as house_id,
  mundipagg_token,
  case
    when coalesce(is_ongoing,false) = TRUE THEN 1
    ELSE 0
  end as is_ongoing
FROM reservation;