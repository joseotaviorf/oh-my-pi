SELECT
  id,  
  sales_flow_id AS id_sales_flow,
  sync_status,  
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.task_manager_info
