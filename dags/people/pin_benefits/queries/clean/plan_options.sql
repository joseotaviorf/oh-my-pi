SELECT
  opt_id AS id_option,
  business_group_id AS id_business_group,
  name AS option_name,
  short_code AS option_short_code,
  short_name AS option_short_name,
  created_by AS created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  invk_wv_opt_flag = 'Y' AS is_invoke_waiver_option,
  global_flag = 'Y' AS is_global,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_benefits_raw.ben_opt_f
