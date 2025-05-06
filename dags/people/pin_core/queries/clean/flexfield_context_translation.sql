SELECT
  application_id AS id_application,
  enterprise_id AS id_enterprise,
  sandbox_id AS id_sandbox,
  context_code,
  created_by,
  last_updated_by AS updated_by,
  descriptive_flexfield_code,
  language,
  source_lang AS source_language,
  name,
  description,
  seed_data_source,
  instruction_help_text,
  ora_seed_set1 = 'Y' AS is_oracle_seed_set_1,
  ora_seed_set2 = 'Y' AS is_oracle_seed_set_2,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.fnd_df_contexts_tl
