select
  sk_task,
  flg_solved,
  score_factor,
  dt_start,
  dt_completed,
  version,
  origin,
  type,
  getdate() as dt_timestamp
from staging.{table_name}
where dt_partition = '{partition_date}'
;