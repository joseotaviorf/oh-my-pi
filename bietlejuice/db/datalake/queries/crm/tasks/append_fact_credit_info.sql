, proposals as (
  select
    t.*,
    cast(coalesce(ep.id, '-1') as bigint) as sk_proposal,
    cast(coalesce(epi.usuario_id, '-1') as bigint) as sk_house_owner,
    cast(coalesce(ep.proponente_id, '-1') as bigint) as sk_tenant
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_raw.ebdb_proposta ep
    on trim(ct.origin) = 'Proposta'
      and cast(ct.id_origin as bigint) = try(cast(ep.id as bigint))
  left join datalake_raw.ebdb_imovel epi
    on epi.id = ep.imovel_id
),
proposal_house_listing as (
  select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_proposal as bigint) as sk_proposal
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_proposal != '-1'
  group by 1, 2
)
select distinct
  p.sk_task,
  p.sk_receiver,
  p.sk_start_date,
  p.sk_completed_date,
  p.sk_origin,
  p.sk_assignee,
  p.action_user_name,
  p.sk_user_action,
  p.sk_action_date,
  p.ts_action,
  p.action_type,
  p.sk_task_user_start_date,
  p.ts_task_user_start,
  p.sk_task_user_end_date,
  p.ts_task_user_end,
  p.task_user_type,
  p.task_user_resolve_hours,
  p.sk_proposal,
  coalesce(phl.sk_house_listing, -1) as sk_house_listing,
  p.sk_house_owner,
  p.sk_tenant,
  p.dt_partition
from proposals p
left join proposal_house_listing phl
 on p.sk_proposal = phl.sk_proposal
   and p.sk_proposal != -1
;