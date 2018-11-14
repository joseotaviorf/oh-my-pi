-- because the incremental load might duplicate date, a grouping must be done
with max_date as (
  select
    ct.id,
    max(ct.dt) as max_dt
  from datalake_clean.crm_tasks ct
  where __WHERE_CLAUSE__
  group by 1
)
select distinct
  ct.id as sk_task,
  try(cast(ct.resolved as boolean)) as flg_solved,
  ct.score_factor,
  ct.ts_start,
  ct.ts_completed,
  round(date_diff('minute', cast(regexp_extract(ct.ts_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp),
                            cast(regexp_extract(ct.ts_completed, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
      ) / 60., 2) as hours_task_start_to_completed,
  ct.v as version,
  ct.origin,
  ct.type,
  array_distinct(array_agg(coalesce(regexp_extract(ct.metadata, 'assunto":"([^"]+)', 1), cw.title)) over (partition by ct.id)) as titles,
  array_distinct(array_agg(coalesce(regexp_extract(ct.metadata, 'workgroupId":"([^"]+)', 1), cw.id)) over (partition by ct.id)) as workgroups,
  cast(ct.dt as date) as ts_partition
from datalake_clean.crm_tasks ct
join max_date md
  on ct.id = md.id
    and ct.dt = md.max_dt
left join datalake_clean.crm_workgroups cw
  on trim(ct.type) = cw.task_type
where __WHERE_CLAUSE__
-- because the query can have another where clause (appended at runtime), a semicolon MUST NOT be added