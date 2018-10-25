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
tasks as (
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
)
-- append data mart specific CTEs in order to populate its fact table (sqls: append_fact_{data mart})