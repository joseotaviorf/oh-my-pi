with actions_prev as (
  select
    dt,
    score_factor,
    dt_start,
    id_receiver,
    id,
    dt_completed,
    regexp_extract_all(actions, '{[^}]+[^,]+[^{]+}') as action_array
  from datalake_clean.crm_tasks_credit
),
actions as (
  select distinct
    ct.dt,
    ct.dt_start,
    ct.id,
    ct.dt_completed,
    cast(json_extract(a.action, '$.username') as varchar) as action_user_name,
    cast(json_extract(a.action, '$.userid') as varchar) as action_user_id,
    cast(cast(json_extract(a.action, '$.date') as varchar) as timestamp) as action_date,
    cast(json_extract(a.action, '$.type') as varchar) as action_type
  from actions_prev ct
  cross join unnest(action_array) as a (action)
)
select
  id as sk_credit_task,
  cast(replace(regexp_extract(dt_start, '\d{4}-\d{2}-\d{2}'), '-', '') as bigint) as sk_task_start_date,
  cast(replace(regexp_extract(dt_completed, '\d{4}-\d{2}-\d{2}'), '-', '') as bigint) as sk_task_end_date,
  cast(coalesce(action_user_id, '-1') as bigint) as sk_task_user,
  coalesce(
    cast(
        replace(regexp_extract(cast((lag(action_date) over (partition by id order by action_date)) as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
      as bigint
    ), -1) as sk_task_user_start_date,
  coalesce(cast(replace(regexp_extract(cast(action_date as varchar), '\d{4}-\d{2}-\d{2}'), '-', '') as bigint), -1) as sk_task_user_end_date,
  action_type as task_user_type,
  if(action_user_name is null, null, round(date_diff('second', lag(action_date) over (partition by id order by action_date), action_date) / 3600.0, 1)) as task_user_resolve_hours
from actions
where dt = '__PARTITION_DATE__'
;