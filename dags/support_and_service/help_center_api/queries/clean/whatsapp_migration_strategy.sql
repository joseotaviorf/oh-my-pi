SELECT
  id AS id_user,
  migration_strategy,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_help_center_api_raw.t_whatsapp_migration_strategy
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
