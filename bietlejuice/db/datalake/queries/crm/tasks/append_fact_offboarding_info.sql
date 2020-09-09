, contracts as (
  select
    t.*,
    cast(coalesce(ec.id, ev.id_contract, -1) as bigint) as sk_contract,
    cast(coalesce(eo.id, -1) as bigint) as sk_rent_flow
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_ebdb_clean_prod.contract ec
    on trim(ct.origin) = 'Contrato'
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = ec.id
  left join datalake_ebdb_clean_prod.rent_flow eo
    on trim(ct.origin) = 'FluxoLocacao'
        and try_cast(try_cast(ct.id_origin as decimal) as bigint) = eo.id
  left join datalake_ebdb_clean_prod.inspection ev
    on trim(ct.origin) = 'Vistoria'
        and try_cast(try_cast(ct.id_origin as decimal) as bigint) = ev.id
),
contract_house_listing as (
  select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_owner as bigint) as sk_house_owner,
    cast(sk_contract as bigint) as sk_contract,
    cast(sk_client as bigint) as sk_tenant,
    cast(sk_rent_flow as bigint) as sk_rent_flow
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_contract != '-1'
  group by 1, 2, 3, 4, 5
)
select distinct
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
  c.sk_task_user_start_date as sk_task_action_start_date,
  c.ts_task_user_start as ts_task_action_start,
  c.sk_task_user_end_date as sk_task_action_end_date,
  c.ts_task_user_end as ts_task_action_end,
  c.task_user_type as task_action_type,
  c.task_user_resolve_hours,
  coalesce(chl_contract.sk_contract, -1) as sk_contract,
  coalesce(chl_contract.sk_house_listing, chl_rent_flow.sk_house_listing, -1) as sk_house_listing,
  coalesce(chl_contract.sk_house_owner, chl_rent_flow.sk_house_owner, -1) as sk_house_owner,
  coalesce(chl_contract.sk_tenant, chl_rent_flow.sk_tenant, -1) as sk_tenant,
  c.dt_partition
from contracts c
left join contract_house_listing chl_contract
 on c.sk_contract = chl_contract.sk_contract
   and c.sk_contract != -1
left join contract_house_listing chl_rent_flow
    on c.sk_rent_flow = chl_rent_flow.sk_rent_flow
    and c.sk_rent_flow != -1
;