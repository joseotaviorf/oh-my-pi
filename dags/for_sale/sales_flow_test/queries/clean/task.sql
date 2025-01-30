SELECT
  id,
  source_related_id AS id_source_related,
  label,
  subject,
  source,
  task_trigger,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_test_raw.task