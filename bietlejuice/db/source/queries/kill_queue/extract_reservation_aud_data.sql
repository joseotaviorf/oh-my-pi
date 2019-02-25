SELECT
  id,
  rev,
  revtype,
  cast(revend as char) as revend,
  cast(attempt as char) as attempt,
  cast(coalesce(attempt_mod,0) as unsigned) as attempt_mod,
  mundipagg_token,
  cast(coalesce(mundipagg_token_mod,0) as unsigned) as mundipagg_token_mod,
  cast(rent_flow_id as char) as rent_flow_id,
  status,
  cast(coalesce(status_mod,0) as unsigned) as status_mod,
  cast(tenant_id as char) as tenant_id,
  cast(value as char) as value,
  cast(coalesce(value_mod,0) as unsigned) as value_mod,
  cast(house_id as char) as house_id
FROM reservation_aud;