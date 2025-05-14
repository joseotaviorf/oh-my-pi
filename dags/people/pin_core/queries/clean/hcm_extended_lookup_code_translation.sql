SELECT
  enterprise_id AS id_enterprise,
  extended_lookup_code_id AS id_enterprise_extended_lookup_code,
  language,
  source_lang AS source_language_code,
  extended_lookup_code_name,
  created_by,
  last_updated_by AS updated_by,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.hcm_extended_lookup_codes_tl