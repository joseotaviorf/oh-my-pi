SELECT
  id,
  source_offer_id as id_source_offer,
  target_offer_id as id_target_offer,
  rev,
  revtype as rev_type,
  `status`,
  status_mod as mod_status,
  target_offer_mod as mod_target_offer
FROM datalake_godfather_raw.revived_offer_aud
