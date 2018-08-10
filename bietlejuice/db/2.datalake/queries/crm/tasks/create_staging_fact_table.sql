select
  id as sk_task,
  coalesce(cast(id_receiver as bigint), -1) as sk_receiver,
  coalesce(
    cast(
      replace(regexp_extract(cast(dt_start as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
     as bigint
    ), -1) as sk_start_date,
  coalesce(
    cast(
      replace(regexp_extract(cast(dt_completed as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
     as bigint
    ), -1) as sk_completed_date,
  cast(id_origin as bigint) as sk_origin,
  cast(id_assignee as bigint) as sk_assignee,
  action_user_name,
  coalesce(cast(id_user_action as bigint), -1) as sk_user_action,
  coalesce(
    cast(
      replace(regexp_extract(cast(dt_action as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
     as bigint
    ), -1) as sk_action_date,
  dt_action,
  action_type,
  coalesce(
    cast(
      replace(regexp_extract(cast(dt_task_user_start as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
     as bigint
    ), -1) as sk_task_user_start_date,
  dt_task_user_start,
  coalesce(
    cast(
      replace(regexp_extract(cast(dt_task_user_end as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
     as bigint
    ), -1) as sk_task_user_end_date,
  dt_task_user_end,
  task_user_type,
  task_user_resolve_hours,
  cast(dt as date) as dt_partition
from datalake_clean.crm_tasks_resolution
where trim(type) in ('__TYPES__')
  and dt = '__PARTITION_DATE__'
;