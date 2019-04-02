, contracts as (
  select
    t.*,
    cast(coalesce(dc.sk_contract, ec.id, offer_contract.id, fhl.sk_contract, '-1') as bigint) as sk_contract,
    cast(coalesce(eo.id, '-1') as bigint) as sk_rent_flow
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_dim_contract dc
    on trim(ct.origin) = 'Contrato'
      and cast(ct.id_origin as bigint) = try(cast(dc.sk_contract as bigint))
  left join datalake_raw.ebdb_preproposta epp
    on trim(ct.origin) = 'PreProposta'
        and cast(ct.id_origin as bigint) = try(cast(epp.id as bigint))
  left join datalake_raw.ebdb_proposta ep
    on cast(epp.id as bigint) = try(cast(ep.preproposta_id as bigint))
  left join datalake_raw.ebdb_contrato ec
    on cast(ep.id as bigint) = try(cast(ec.proposta_id as bigint))
  left join datalake_raw.ebdb_offer eof
    on trim(ct.origin) = 'Offer'
        and cast(ct.id_origin as bigint) = try(cast(eof.id as bigint))
  left join datalake_raw.ebdb_proposta offer_prop
    on offer_prop.offer_id = eof.id
  left join datalake_raw.ebdb_contrato offer_contract
    on cast(offer_prop.id as bigint) = try(cast(offer_contract.proposta_id as bigint))
  left join datalake_raw.ebdb_fluxolocacao eo
    on trim(ct.origin) = 'FluxoLocacao'
        and cast(ct.id_origin as bigint) = try(cast(eo.id as bigint))
  left join datalake_clean.ods_dim_house_listing dhl
    on trim(ct.origin) = 'Imovel'
      and cast(ct.id_origin as bigint) = try(cast(dhl.id_house as bigint))
      and cast(regexp_extract(ct.ts_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
        between cast(regexp_extract(dhl.ts_listing_version_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
          and (case
                 when dhl.ts_listing_version_end = ''
                   then now()
                 else cast(regexp_extract(dhl.ts_listing_version_end, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
               end)
  left join datalake_clean.ods_fact_house_listings fhl
    on fhl.sk_house_listing = dhl.sk_house_listing
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
  coalesce(chl_contract.sk_contract, chl_rent_flow.sk_contract, -1) as sk_contract,
  c.dt_partition
from contracts c
left join contract_house_listing chl_contract
 on c.sk_contract = chl_contract.sk_contract
   and c.sk_contract != -1
left join contract_house_listing chl_rent_flow
    on c.sk_rent_flow = chl_rent_flow.sk_rent_flow
    and c.sk_rent_flow != -1
;
