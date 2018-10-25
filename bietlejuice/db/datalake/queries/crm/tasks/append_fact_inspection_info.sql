, contracts as (
  select
    t.*,
    cast(coalesce(dc.sk_contract, ev.contrato_id, '-1') as bigint) as sk_contract
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_dim_contract dc
    on trim(ct.origin) = 'Contrato'
      and cast(ct.id_origin as bigint) = cast(dc.sk_contract as bigint)
  left join datalake_raw.ebdb_vistoria ev
    on trim(ct.origin) = 'Vistoria'
      and cast(ct.id_origin as bigint) = cast(ev.id as bigint)
),
contract_house_listing as (
  select
    cast(sk_house as bigint) as sk_house_listing,
    cast(sk_contract as bigint) as sk_contract
  from datalake_clean.ods_fact_demand
  where sk_contract != '-1'
  group by 1, 2
)
select
  c.sk_task,
  c.sk_receiver,
  c.sk_start_date,
  c.sk_completed_date,
  c.sk_origin,
  c.sk_assignee,
  c.action_user_name,
  c.sk_user_action,
  c.sk_action_date,
  c.ts_action,
  c.action_type,
  c.sk_task_user_start_date,
  c.ts_task_user_start,
  c.sk_task_user_end_date,
  c.ts_task_user_end,
  c.task_user_type,
  c.task_user_resolve_hours,
  c.sk_contract,
  coalesce(chl.sk_house_listing, -1) as sk_house_listing,
  c.dt_partition
from contracts c
left join contract_house_listing chl
 on c.sk_contract = chl.sk_contract
   and c.sk_contract != -1
;