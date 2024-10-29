SELECT
  id,
  task_id AS id_task,
  label,
  type,
  target,
  deadline,
  activation_trigger,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.subtask
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}