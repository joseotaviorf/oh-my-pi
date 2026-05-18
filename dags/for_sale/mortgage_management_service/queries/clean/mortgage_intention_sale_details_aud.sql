SELECT
  id,
  rev,
  revtype AS rev_type,
  revend AS rev_end,
  mortgage_intention_id AS id_mortgage_intention,
  sale_reference_id,
  inspection_companion_name AS inspection_companion_person_name,
  inspection_companion_phone AS inspection_companion_phone_number,
  version,
  mortgage_intention_id_mod AS mod_id_mortgage_intention,
  sale_reference_id_mod AS mod_sale_reference_id,
  inspection_companion_name_mod AS mod_inspection_companion_person_name,
  inspection_companion_phone_mod AS mod_inspection_companion_phone_number,
  version_mod AS mod_version,
  created_at_mod AS mod_ts_created,
  updated_at_mod AS mod_ts_updated,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_intention_sale_details_aud
