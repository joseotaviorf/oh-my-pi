, proposals_contracts as (
  select
    t.sk_task,
    t.sk_receiver,
    t.sk_origin,
    t.sk_assignee,
    t.sk_user_action,
    t.sk_start_date,
    t.sk_completed_date,
    t.sk_next_action_date,
    t.sk_action_date,
    t.action_user_name,
    t.action_type,
    t.action_reason,
    t.task_status,
    t.minutes_task_created_to_started,
    t.task_user_resolve_hours,
    t.ts_next_action,
    t.ts_action,
    t.dt_partition,
    coalesce(ep.id, ec.id_proposal) as sk_proposal,
    coalesce(ec.id, epc.id) as sk_contract,
    coalesce(epi.id_user, eci.id_user) as sk_house_owner,
    coalesce(ep.id_proponent, ec.id_user) as sk_tenant,
    cast(coalesce(eo.sk_offer, feo.sk_offer) as bigint) as sk_offer
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_ebdb_clean_prod.contract ec
    on trim(ct.origin) in ('Contrato', 'ContratoFull')
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = ec.id
  left join datalake_ebdb_clean_prod.house eci
    on eci.id = ec.id_house
  left join datalake_ebdb_clean_prod.proposal ep
    on trim(ct.origin) = 'Proposta'
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = ep.id
  left join datalake_ebdb_clean_prod.contract epc
    on epc.id_proposal = ep.id
  left join datalake_ebdb_clean_prod.house epi
    on epi.id = epc.id_house
  left join datalake_clean.ods_dim_offer eo
    on trim(ct.origin) = 'Offer'
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(eo.id_offer as bigint)
  left join datalake_clean.ods_dim_offer feo
    on trim(ct.origin) = 'Offer'
     and ct.id_origin = feo.id_firestore
),
contract_proposal_house_listing as (
  select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_offer as bigint) as sk_offer,
    cast(sk_proposal as bigint) as sk_proposal,
    cast(sk_owner as bigint) as sk_house_owner,
    cast(coalesce(if(sk_contract != '-1',sk_client),'-1') as bigint) as sk_tenant,
    cast(coalesce(if(sk_proposal != '-1',sk_client),'-1') as bigint) as sk_proponent,
    max(cast(sk_contract as bigint)) as sk_contract
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_contract != '-1'
    or sk_proposal != '-1'
    or sk_offer != '-1'
  group by 1, 2, 3, 4, 5, 6
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
  pc.action_reason,
  pc.task_status,
  pc.sk_action_date as sk_task_user_start_date,
  pc.ts_action as ts_task_user_start,
  pc.sk_next_action_date as sk_task_user_end_date,
  pc.ts_next_action as ts_task_user_end,
  pc.action_type as task_user_type,
  pc.minutes_task_created_to_started,
  pc.task_user_resolve_hours,
  coalesce(contract.sk_offer, pc.sk_offer,offer.sk_offer, pc.sk_offer, -1) as sk_offer,
  coalesce(contract.sk_proposal, pc.sk_proposal, offer.sk_proposal,-1) as sk_proposal,
  coalesce(proposal.sk_contract, pc.sk_contract, offer.sk_contract,-1) as sk_contract,
  coalesce(proposal.sk_house_listing, contract.sk_house_listing, offer.sk_house_listing, -1) as sk_house_listing,
  coalesce(contract.sk_house_owner, proposal.sk_house_owner, offer.sk_house_owner, pc.sk_house_owner,-1) as sk_house_owner,
  coalesce(contract.sk_tenant, proposal.sk_tenant, offer.sk_tenant, pc.sk_tenant, -1) as sk_tenant,
  coalesce(contract.sk_proponent, proposal.sk_proponent, offer.sk_proponent, -1) as sk_proponent,
  pc.dt_partition
from proposals_contracts pc
left join contract_proposal_house_listing proposal
 on pc.sk_proposal = proposal.sk_proposal
   and pc.sk_proposal != -1
-- the left joins below avoids a cartesian product made with an 'or'
left join contract_proposal_house_listing contract
 on pc.sk_contract = contract.sk_contract
   and pc.sk_contract != -1
left join contract_proposal_house_listing offer
 on pc.sk_offer = offer.sk_offer
   and pc.sk_offer != -1
;