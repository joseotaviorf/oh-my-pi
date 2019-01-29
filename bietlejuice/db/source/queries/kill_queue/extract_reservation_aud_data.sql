SELECT
  id,
  rev,
  revtype,
  cast(revend as char) as revend,
  attempt,
  cast(coalesce(attempt_mod,0) as unsigned) as attempt_mod,
  mundipagg_token,
  cast(coalesce(mundipagg_token_mod,0) as unsigned) as mundipagg_token_mod,
  rent_flow_id,
  status,
  cast(coalesce(status_mod,0) as unsigned) as status_mod,
  tenant_id,
  value,
  cast(coalesce(value_mod,0) as unsigned) as value_mod,
  house_id
FROM reservation_aud;