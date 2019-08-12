, contracts as (
  select
    t.*,
    dc.sk_contract as dc_sk_contract,
    cast(coalesce(dc.sk_contract, ec.id, offer_contract.id) as bigint) as sk_contract,
    cast(coalesce(eo.id) as bigint) as sk_rent_flow
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_dim_contract dc
    on trim(ct.origin) = 'Contrato'
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(dc.sk_contract as bigint)
  left join datalake_raw.ebdb_preproposta epp
    on trim(ct.origin) = 'PreProposta'
        and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(epp.id as bigint)
  left join datalake_raw.ebdb_proposta ep
    on epp.id = ep.preproposta_id
  left join datalake_raw.ebdb_contrato ec
    on ep.id = ec.proposta_id
  left join datalake_raw.ebdb_offer eof
    on trim(ct.origin) = 'Offer'
        and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(eof.godfatherid as bigint)
  left join datalake_raw.ebdb_proposta offer_prop
    on offer_prop.offer_id = eof.id
  left join datalake_raw.ebdb_contrato offer_contract
    on try_cast(offer_prop.id as bigint) = try_cast(offer_contract.proposta_id as bigint)
  left join datalake_raw.ebdb_fluxolocacao eo
    on trim(ct.origin) = 'FluxoLocacao'
        and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(eo.id as bigint)
),
contract_house_listing as (
  select
    cast(sk_contract as bigint) as sk_contract,
    cast(sk_rent_flow as bigint) as sk_rent_flow
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_contract != '-1'
  group by 1, 2
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
  coalesce(chl_rent_flow.sk_contract, c.sk_contract, -1) as sk_contract,
  c.dt_partition
from contracts c
left join contract_house_listing chl_rent_flow
    on c.sk_rent_flow = chl_rent_flow.sk_rent_flow
    and c.sk_contract is null