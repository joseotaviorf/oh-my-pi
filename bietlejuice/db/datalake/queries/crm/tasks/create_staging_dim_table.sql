-- because the incremental load might duplicate date, a grouping must be done
with max_date as (
  select
    ct.id,
    max(ct.dt) as max_dt
  from datalake_clean.crm_tasks ct
  where __WHERE_CLAUSE__
  group by 1
)
select
  ct.id as sk_task,
  cast(ct.solved as boolean) as flg_solved,
  ct.score_factor,
  ct.dt_start,
  ct.dt_completed,
  round(date_diff('minute', cast(regexp_extract(ct.dt_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp),
                            cast(regexp_extract(ct.dt_completed, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
      ) / 60., 2) as hours_task_start_to_completed,
  ct.version,
  ct.origin,
  ct.type,
  coalesce(regexp_extract(ct.metadata, 'assunto":"([^"]+)', 1), cw.title) as title,
  coalesce(regexp_extract(ct.metadata, 'workgroupid":"([^"]+)', 1), cw.id) as id_workgroup,
  cast(ct.dt as date) as dt_partition
from datalake_clean.crm_tasks ct
join max_date md
  on ct.id = md.id
    and ct.dt = md.max_dt
left join datalake_clean.crm_workgroups cw
  on trim(ct.type) = cw.task_type
where __WHERE_CLAUSE__
-- because the query can have another where clause (appended at runtime), a semicolon MUST NOT be added