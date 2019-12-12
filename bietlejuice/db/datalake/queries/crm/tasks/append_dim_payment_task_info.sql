,
max_request_date as (
    select
      cast(id_external_contract as varchar) as id_external_contract,
      max(json_extract_scalar(activity.metadata, '$.request_date')) as max_date
    from datalake_heimdall_clean_prod.activity activity
    group by 1
),
last_activity_refund as (
  select m.id_external_contract, activity.status as status, m.max_date as max_date
  from datalake_heimdall_clean_prod.activity activity
  join max_request_date m
    on cast(activity.id_external_contract as varchar) = m.id_external_contract
      and m.max_date = json_extract_scalar(activity.metadata, '$.request_date')
)
select distinct
  ct.sk_task,
  ct.flg_solved,
  activity.status as tenant_refund_status,
  ct.score_factor,
  ct.ts_start,
  ct.ts_completed,
  ct.ts_silenced_until,
  ct.hours_task_start_to_completed,
  ct.version,
  ct.origin,
  ct.type,
  ct.is_task_auto_completed,
  substr(ct.description, 1, 5000) as description,
  ct.subject,
  ct.titles,
  ct.workgroups,
  ct.ts_partition
from tasks ct
join datalake_clean.crm_tasks tasks
    on ct.sk_task = tasks.id
      and cast(ct.ts_partition as varchar) = tasks.dt
left join last_activity_refund activity
  on cast(id_external_contract as varchar) = json_extract_scalar(tasks.metadata, '$.contract_id')
     and activity.max_date = json_extract_scalar(tasks.metadata, '$.request_date')