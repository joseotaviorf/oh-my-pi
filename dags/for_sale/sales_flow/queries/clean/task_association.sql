SELECT
  id,
  subtask_id AS id_subtask,
  main_user_id AS id_main_user,
  sales_flow_id AS id_sales_flow,
  status,
  attributes,
  released_at AS ts_released,
  concluded_at AS ts_concluded,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.task_association
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}