SELECT
  lookup_code,
  lookup_type,
  created_by,
  last_updated_by AS updated_by,
  description AS lookup_description,
  meaning,
  tag,
  CAST(display_sequence AS INT) AS display_sequence,
  enabled_flag = 'Y' AS is_enabled,
  TO_DATE(start_date_active) AS dt_active_started,
  TO_DATE(end_date_active) AS dt_active_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.hr_lookups