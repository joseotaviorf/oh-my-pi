, contracts_offers as (
  select
    t.*,
    cast(coalesce(dc.sk_contract, cast(ec.id as varchar)) as bigint) as sk_contract,
    ep.id as sk_proposal,
    cast(coalesce(eo.sk_offer, feo.sk_offer) as bigint) as sk_offer,
    erf.id as sk_rent_flow
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_dim_contract dc
    on trim(ct.origin) = 'Contrato'
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(dc.sk_contract as bigint)
  left join datalake_ebdb_clean_prod.pre_proposal epp
    on trim(ct.origin) = 'PreProposta'
        and try_cast(try_cast(ct.id_origin as decimal) as bigint) = epp.id
  left join datalake_ebdb_clean_prod.proposal ep
    on epp.id = ep.id_pre_proposal
  left join datalake_ebdb_clean_prod.contract ec
    on ep.id = ec.id_proposal
  left join datalake_clean.ods_dim_offer eo
    on trim(ct.origin) = 'Offer'
      and regexp_like(ct.id_origin, '\D') = false
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(eo.id_offer as bigint)
  left join datalake_clean.ods_dim_offer feo
    on trim(ct.origin) = 'Offer'
     and regexp_like(ct.id_origin, '\D') = true
     and ct.id_origin = feo.id_firestore
  left join datalake_ebdb_clean_prod.rent_flow erf
    on trim(ct.origin) = 'FluxoLocacao'
        and regexp_like(ct.id_origin, '\D') = false
        and try_cast(try_cast(ct.id_origin as decimal) as bigint) = erf.id
),
contract_offer_house_listing as (
  select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_rent_flow as bigint) as sk_rent_flow,
    cast(sk_offer as bigint) as sk_offer,
    cast(sk_proposal as bigint) as sk_proposal,
    cast(sk_owner as bigint) as sk_house_owner,
    cast(coalesce(if(sk_contract != '-1',sk_client),'-1') as bigint) as sk_tenant,
    cast(coalesce(if(sk_proposal != '-1',sk_client),'-1') as bigint) as sk_proponent,
    max(cast(sk_contract as bigint)) as sk_contract
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_contract != '-1'
    or sk_offer != '-1'
  group by 1, 2, 3, 4, 5, 6, 7
)
select distinct
  co.sk_task,
  co.sk_receiver,
  co.sk_start_date,
  co.sk_completed_date,
  co.sk_origin,
  co.sk_assignee,
  co.action_user_name,
  co.sk_user_action,
  co.sk_action_date,
  co.ts_action,
  co.action_type,
  co.sk_task_user_start_date as sk_task_action_start_date,
  co.ts_task_user_start as ts_task_action_start,
  co.sk_task_user_end_date as sk_task_action_end_date,
  co.ts_task_user_end as ts_task_action_end,
  co.task_user_type as task_action_type,
  co.task_user_resolve_hours,
  coalesce(co.sk_offer, chl_rent_flow.sk_offer, chl_contract.sk_offer, chl_offer.sk_offer,-1) as sk_offer,
  coalesce(co.sk_proposal, chl_rent_flow.sk_proposal, chl_contract.sk_proposal, chl_offer.sk_proposal,-1) as sk_proposal,
  coalesce(co.sk_contract, chl_rent_flow.sk_contract, chl_offer.sk_contract, -1) as sk_contract,
  coalesce(chl_rent_flow.sk_house_listing, chl_contract.sk_house_listing, chl_offer.sk_house_listing, -1) as sk_house_listing,
  coalesce(chl_rent_flow.sk_house_owner, chl_contract.sk_house_owner, chl_offer.sk_house_owner, -1) as sk_house_owner,
  coalesce(chl_rent_flow.sk_tenant, chl_contract.sk_tenant, chl_offer.sk_tenant, -1) as sk_tenant,
  coalesce(chl_rent_flow.sk_proponent, chl_contract.sk_proponent, chl_offer.sk_proponent, -1) as sk_proponent,
  co.dt_partition
from contracts_offers co
left join contract_offer_house_listing chl_rent_flow
    on co.sk_rent_flow = chl_rent_flow.sk_rent_flow
left join contract_offer_house_listing chl_contract
    on co.sk_contract = chl_contract.sk_contract
left join contract_offer_house_listing chl_offer
    on co.sk_offer = chl_offer.sk_offer
;
