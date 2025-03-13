SELECT
  id,
  referenceid AS id_reference,
  dimensionentity_id AS id_dimension_entity,
  country AS country_code,
  address,
  rev,
  revtype,
  revend,
  status,
  whatsappoptedin,
  longtail,
  scoringinfo AS scoring_info,
  referenceid_mod AS mod_id_reference,
  longtail_mod AS mod_longtail,
  whatsappoptedin_mod AS mod_whatsappoptedin,
  dimensionentity_mod AS mod_dimension_entity,
  status_mod AS mod_status,
  scoringinfo_mod AS mod_scoring_info
FROM
  datalake_wololo_raw.prospect_aud
