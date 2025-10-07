SELECT
  id AS id_user,
  migration_strategy,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_help_center_api_raw.t_whatsapp_migration_strategy
