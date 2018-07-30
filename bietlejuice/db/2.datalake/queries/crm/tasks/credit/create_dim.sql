select
  id as sk_credit_task,
  id_origin,
  id_assignee,
  solved as flg_solved,
  score_factor,
  dt_start as dt_task_start,
  dt_completed as dt_task_end,
  version,
  origin,
  id_receiver,
  type
from datalake_clean.crm_tasks_credit
where dt = '__PARTITION_DATE__'
;