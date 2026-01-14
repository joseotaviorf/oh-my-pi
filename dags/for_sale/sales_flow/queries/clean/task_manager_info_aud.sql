SELECT
  id,
  rev,
  revtype AS rev_type,
  revend AS rev_end,
  sales_flow_id AS id_sales_flow,
  sales_flow_id_mod AS mod_id_sales_flow,
  sync_status,  
  sync_status_mod AS mod_sync_status,
  created_at AS ts_created,
  created_at_mod AS mod_ts_created,
  updated_at AS ts_updated,
  updated_at_mod AS mod_ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.task_manager_info_aud