SELECT
  id,
  rent_id as id_rent,
  rev,
  revtype as rev_type,
  `status`,
  status_mod as mod_status
FROM
  datalake_godfather_raw.rent_flow_aud
