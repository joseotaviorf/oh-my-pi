select
  sk_task,
  flg_solved,
  score_factor,
  dt_start,
  dt_completed,
  hours_task_start_to_completed,
  version,
  origin,
  type,
  title,
  id_workgroup,
  getdate() as dt_timestamp
from staging.{table_name}
-- because the query can have another where clause (appended at runtime), a semicolon MUST NOT be added