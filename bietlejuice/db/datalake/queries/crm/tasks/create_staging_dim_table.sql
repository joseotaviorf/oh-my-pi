select
  id as sk_task,
  solved as flg_solved,
  score_factor,
  dt_start,
  dt_completed,
  version,
  origin,
  type,
  cast(dt as date) as dt_partition
from datalake_clean.crm_tasks
where trim(type) in ('__TYPES__')
  and dt = '__PARTITION_DATE__'
;