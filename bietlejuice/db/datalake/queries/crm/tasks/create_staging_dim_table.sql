-- because the incremental load might duplicate date, a grouping must be done
with tasks_resolution as (
  with tasks_resolution_max_date as (
    select
      ct.id,
      max(ct.dt) as max_dt
    from datalake_clean.crm_tasks_resolution ct
    -- clause that represents the string of which will be replaced by all the automatic task types and manual workgroups
    where __WHERE_CLAUSE__
      and ct.action_type in ('RESOLVE', 'REALIZE')
    group by 1
  ),
  tasks_resolution_max_action_date as (
    select
      ct.id,
      ct.ts_action,
      nullif(ct.id_user_action, '') is null as is_task_auto_completed,
      row_number() over (partition by ct.id order by ct.ts_action desc) as rn
    from datalake_clean.crm_tasks_resolution ct
    join tasks_resolution_max_date trmd
      on ct.id = trmd.id
        and ct.dt = trmd.max_dt
    -- clause that represents the string of which will be replaced by all the automatic task types and manual workgroups
    where __WHERE_CLAUSE__
      and ct.action_type in ('RESOLVE', 'REALIZE')
  )
  select
    id,
    ts_action,
    is_task_auto_completed
  from tasks_resolution_max_action_date
  where rn = 1
),
tasks as (
  with tasks_max_date as (
    select
      ct.id,
      max(ct.dt) as max_dt
    from datalake_clean.crm_tasks ct
    where __WHERE_CLAUSE__
    group by 1
  ),
  min_analyst_started as (
    select
      id,
      min(json_extract_scalar(sl.started_entry, '$.date')) as min_ts_analyst_started
    from datalake_clean.crm_tasks ct
    cross join unnest(cast(json_parse(analyst_started_list) as array(json))) as sl (started_entry)
    where __WHERE_CLAUSE__
      and analyst_started_list != '[]' -- avoid analysing empty arrays
    group by 1
  )
  select distinct
    cast(ct.id as varchar) as sk_task,
    try(cast(ct.resolved as boolean)) as flg_solved,
    cast(ct.score_factor as integer) as score_factor,
    cast(regexp_extract(trim(ct.ts_start), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as ts_start,
    cast(regexp_extract(trim(coalesce(tr.ts_action, ct.ts_completed)), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as ts_completed,
    cast(regexp_extract(trim(ct.ts_silenced_until), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as ts_silenced_until,
    cast(regexp_extract(trim(mas.min_ts_analyst_started), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as ts_analyst_started,
    round(date_diff('minute', cast(regexp_extract(ct.ts_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp),
                              cast(regexp_extract(coalesce(tr.ts_action, ct.ts_completed), '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
        ) / 60., 2) as hours_task_start_to_completed,
    cast(ct.v as integer) as version,
    cast(ct.origin as varchar) as origin,
    cast(ct.type as varchar) as type,
    coalesce(tr.is_task_auto_completed, false) as is_task_auto_completed,
    substr(json_format(json_extract(ct.metadata, '$.descricao')), 1, 5000) as description,
    cast(ct.subject as varchar) as subject,
    array_distinct(array_agg(coalesce(regexp_extract(ct.metadata, 'assunto":"([^"]+)', 1), cw.title)) over (partition by ct.id)) as titles,
    array_distinct(array_agg(coalesce(regexp_extract(ct.metadata, 'workgroupId":"([^"]+)', 1), cw.id)) over (partition by ct.id)) as workgroups,
    cast(ct.dt as date) as ts_partition
  from datalake_clean.crm_tasks ct
  join tasks_max_date md
    on ct.id = md.id
      and ct.dt = md.max_dt
  left join datalake_clean.crm_workgroups cw
    on trim(ct.type) = cw.task_type
  left join tasks_resolution tr
    on tr.id = ct.id
  left join min_analyst_started mas
    on mas.id = ct.id
  where __WHERE_CLAUSE__
)