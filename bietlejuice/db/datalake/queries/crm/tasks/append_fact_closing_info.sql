, proposals_contracts as (
  select
    t.*,
    cast(coalesce(ep.id, ec.proposta_id, '-1') as bigint) as sk_proposal,
    cast(coalesce(ec.id, epc.id, '-1') as bigint) as sk_contract,
    cast(coalesce(epi.usuario_id, eci.usuario_id, '-1') as bigint) as sk_house_owner,
    cast(coalesce(ep.proponente_id, ec.usuario_id, '-1') as bigint) as sk_tenant
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_raw.ebdb_contrato ec
    on trim(ct.origin) in ('Contrato', 'ContratoFull')
      and cast(ct.id_origin as bigint) = try(cast(ec.id as bigint))
  left join datalake_raw.ebdb_imovel eci
    on eci.id = ec.imovel_id
  left join datalake_raw.ebdb_proposta ep
    on trim(ct.origin) = 'Proposta'
      and cast(ct.id_origin as bigint) = try(cast(ep.id as bigint))
  left join datalake_raw.ebdb_contrato epc
    on epc.proposta_id = ep.id
  left join datalake_raw.ebdb_imovel epi
    on epi.id = epc.imovel_id
),
contract_proposal_house_listing as (
  select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_proposal as bigint) as sk_proposal,
    cast(sk_contract as bigint) as sk_contract
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_contract != '-1'
    or sk_proposal != '-1'
  group by 1, 2, 3
)
select distinct
  pc.sk_task,
  pc.sk_receiver,
  pc.sk_start_date,
  pc.sk_completed_date,
  pc.sk_origin,
  pc.sk_assignee,
  pc.action_user_name,
  pc.sk_user_action,
  pc.sk_action_date,
  pc.ts_action,
  pc.action_type,
  pc.sk_task_user_start_date,
  pc.ts_task_user_start,
  pc.sk_task_user_end_date,
  pc.ts_task_user_end,
  pc.task_user_type,
  pc.task_user_resolve_hours,
  coalesce(pc.sk_proposal, contract.sk_proposal) as sk_proposal,
  coalesce(pc.sk_contract, proposal.sk_contract) as sk_contract,
  coalesce(proposal.sk_house_listing, contract.sk_house_listing, -1) as sk_house_listing,
  pc.sk_house_owner,
  pc.sk_tenant,
  pc.dt_partition
from proposals_contracts pc
left join contract_proposal_house_listing proposal
 on pc.sk_proposal = proposal.sk_proposal
   and pc.sk_proposal != -1
-- the left join below avoids a cartesian product made with an 'or'
left join contract_proposal_house_listing contract
 on pc.sk_contract = contract.sk_contract
   and pc.sk_contract != -1
;