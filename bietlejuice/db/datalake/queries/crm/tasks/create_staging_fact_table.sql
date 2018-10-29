-- because the incremental load might duplicate date, a grouping must be done
with max_date as (
  select
    ct.id,
    max(ct.dt) as max_dt
  from datalake_clean.crm_tasks_resolution ct
  -- clause that represents the string of which will be replaced by all the automatic task types and manual workgroups
  where __WHERE_CLAUSE__
  group by 1
),
prev_tasks as (
  -- because the incremental load might duplicate date, a distinct must be added
  select distinct
    ct.id as sk_task,
    coalesce(cast(cast(ct.id_receiver as decimal) as bigint), -1) as sk_receiver,
    coalesce(
      cast(
        replace(regexp_extract(cast(ct.ts_start as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
       as bigint
      ), -1) as sk_start_date,
    coalesce(
      cast(
        replace(regexp_extract(cast(ct.ts_completed as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
       as bigint
      ), -1) as sk_completed_date,
    coalesce(cast(cast(ct.id_origin as decimal) as bigint), -1) as sk_origin,
    coalesce(cast(cast(ct.id_assignee as decimal) as bigint), -1) as sk_assignee,
    ct.action_user_name,
    coalesce(cast(cast(ct.id_user_action as decimal) as bigint), -1) as sk_user_action,
    coalesce(
      cast(
        replace(regexp_extract(cast(ct.ts_action as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
       as bigint
      ), -1) as sk_action_date,
    ct.ts_action,
    ct.action_type,
    coalesce(
      cast(
        replace(regexp_extract(cast(ct.ts_task_user_start as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
       as bigint
      ), -1) as sk_task_user_start_date,
    ts_task_user_start,
    coalesce(
      cast(
        replace(regexp_extract(cast(ct.ts_task_user_end as varchar), '\d{4}-\d{2}-\d{2}'), '-', '')
       as bigint
      ), -1) as sk_task_user_end_date,
    ct.ts_task_user_end,
    ct.task_user_type,
    ct.task_user_resolve_hours,
    cast(ct.dt as date) as dt_partition
  from datalake_clean.crm_tasks_resolution ct
  join max_date md
    on ct.id = md.id
      and ct.dt = md.max_dt
  -- clause that represents the string of which will be replaced by all the automatic task types and manual workgroups
  where __WHERE_CLAUSE__
),
-- In some cases, the same user can complete the same task more than once.
-- So, a max grouping is necessary to retrieve only the newest REALIZE action to the CRM models.
prev_max_realized_by_user as (
  select
    sk_task,
    sk_user_action,
    max(ts_action) as max_ts_action
  from prev_tasks
  where action_type = 'REALIZE'
    and sk_user_action != -1
  group by 1, 2
),
max_realized_by_user as (
  select
    t.sk_task,
    t.sk_user_action,
    t.action_type,
    t.sk_task_user_start_date,
    t.ts_task_user_start,
    t.sk_task_user_end_date,
    t.ts_task_user_end,
    t.sk_action_date,
    t.ts_action,
    t.task_user_resolve_hours
  from prev_tasks t
  join prev_max_realized_by_user prev_max
    on t.sk_task = prev_max.sk_task
      -- because the same analyst can have multiple names under the same sk, the join has to be done with the latter.
      and t.sk_user_action = prev_max.sk_user_action
      and t.ts_action = prev_max.max_ts_action
      -- because Athena's MapReduce analyzes both queries separately,
      -- null users from prev_tasks would end up getting evaluated,
      -- thus generation a null -> varchar -> decimal conversion error
      -- so, the following join clause has to be added in order to apply the filter at the beginning of the evaluation.
      and t.action_type = 'REALIZE'
),
tasks as (
  select distinct
    t.sk_task,
    t.sk_receiver,
    t.sk_start_date,
    t.sk_completed_date,
    t.sk_origin,
    t.sk_assignee,
    t.action_user_name,
    t.sk_user_action,
    coalesce(mrbu.sk_action_date, t.sk_action_date) as sk_action_date,
    coalesce(mrbu.ts_action, t.ts_action) as ts_action,
    t.action_type,
    coalesce(mrbu.sk_task_user_start_date, t.sk_task_user_start_date) as sk_task_user_start_date,
    coalesce(mrbu.ts_task_user_start, t.ts_task_user_start) as ts_task_user_start,
    coalesce(mrbu.sk_task_user_end_date, t.sk_task_user_end_date) as sk_task_user_end_date,
    coalesce(mrbu.ts_task_user_end, t.ts_task_user_end) as ts_task_user_end,
    t.task_user_type,
    coalesce(mrbu.task_user_resolve_hours, t.task_user_resolve_hours) as task_user_resolve_hours,
    t.dt_partition
  from prev_tasks t
  left join max_realized_by_user mrbu
    on t.sk_task = mrbu.sk_task
      and t.sk_user_action = mrbu.sk_user_action
      and t.action_type = mrbu.action_type
  -- due to a bug in CRM, the status REALIZE can have no users attached to it
  -- that scenario should only be possible with the RESOLVE status.
  where not(t.sk_user_action != -1
      and t.task_user_type = 'REALIZE')
)
-- append data mart specific CTEs in order to populate its fact table (sqls: append_fact_{data mart})