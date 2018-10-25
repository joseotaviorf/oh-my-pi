select
  sk_task,
  sk_receiver,
  sk_start_date,
  sk_completed_date,
  sk_origin,
  sk_assignee,
  action_user_name,
  sk_user_action,
  sk_action_date,
  ts_action,
  action_type,
  sk_task_user_start_date,
  ts_task_user_start,
  sk_task_user_end_date,
  ts_task_user_end,
  task_user_type,
  task_user_resolve_hours,
  sk_origin as sk_lead,
  dt_partition
from tasks
;