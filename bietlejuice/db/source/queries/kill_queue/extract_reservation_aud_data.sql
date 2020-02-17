SELECT
  id,
  rev,
  rev_type as revtype,
  rev_end as revend,
  attempt,
  case
    when coalesce(is_attempt_mod,false) = TRUE THEN 1
    ELSE 0
  end as attempt_mod,
  mundipagg_token,
  case
    when coalesce(is_value_mod,false) = TRUE THEN 1
    ELSE 0
  end as mundipagg_token_mod,
  id_rent_flow as rent_flow_id,
  status,
  case
    when coalesce(is_status_mod,false) = TRUE THEN 1
    ELSE 0
  end as status_mod,
  id_tenant as tenant_id,
  value,
  case
    when coalesce(is_value_mod,false) = TRUE THEN 1
    ELSE 0
  end as value_mod,
  id_house as house_id
FROM reservation_aud;