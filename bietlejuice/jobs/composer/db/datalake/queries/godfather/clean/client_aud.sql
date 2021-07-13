SELECT
  id,
  rev,
  revtype as rev_type,
  name,
  email,
  cellphone,
  tenant_ongoing_offer,
  tenant_ongoing_offer_mod as mod_tenant_ongoing_offer,
  login_hash
FROM
  datalake_godfather_raw.client_aud
