select
  sk_task,
  flg_solved,
  score_factor,
  ts_start,
  ts_completed,
  ts_silenced_until,
  hours_task_start_to_completed,
  version,
  origin,
  type,
  is_task_auto_completed,
  description,
  subject,
  titles,
  workgroups,
  getdate() as ts_load
from staging.{table_name}
-- because the query can have another where clause (appended at runtime), a semicolon MUST NOT be added