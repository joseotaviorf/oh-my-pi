drop view if exists vw_fact_liquidity_property_scheduling;

create view vw_fact_liquidity_property_scheduling
as
select
  id_property_scheduling as ods_id,
  -- coalesce(f.id_imovel, -1) as sk_property,
  coalesce((f.id_imovel || '00' || coalesce(p."version", '1'))::bigint, -1::bigint) as sk_property,
  p."version"::integer as listing_number,
  coalesce(b.id, -1) as sk_booking,
  coalesce(id_owner, -1) as sk_owner,
  coalesce(id_user_affiliate, -1) as sk_user_affiliate,
  coalesce(f.id_user_agent, -1) as sk_user_agent,
  coalesce(f.id_user_visitor, -1) as sk_user_visitor,
  coalesce(f.id_user_visit_agent, -1) as sk_user_visit_agent,
  coalesce(f.id_visit, -1) as sk_visit,
  coalesce(f.id_negotiation, -1) as sk_negotiation,
  coalesce(f.id_pre_proposal, -1) as sk_pre_proposal,
  coalesce(f.id_proposal, -1) as sk_proposal,
  coalesce(f.id_contract, -1) as sk_contract,
  coalesce(f.id_rental_flow, -1) as id_rental_flow,
  dt_contract_anullment,
  visit_created_from_app,
  visit_created_type,
  visit_last_updated_from_app,
  visit_last_updated_type,

  /*
  esv.initial_utm_source as initial_source,
  esv.initial_utm_medium as initial_medium,
  esv.initial_utm_campaign as initial_campaign,
  esv.initial_referring_domain  as initial_referring_domain,
  esv.utm_source as source,
  esv.utm_medium as medium,
  esv.utm_campaign as campaign,
  esv.referring_domain as referring_domain,
  */

  '' as initial_source,
  '' as initial_medium,
  '' as initial_campaign,
  ''  as initial_referring_domain,

  '' as source,
  '' as medium,
  '' as campaign,
  '' as referring_domain,

  -- ratear custo do dia pelos imoveis publicados no dia determinado
  h.vl_cost_marketing_campaigns_per_published_listings
  	/ coalesce(nullif(count(1) over (partition by f.id_imovel),0),1)
  as vl_cost_marketing_campaigns,

  h.vl_cost_marketing_ads_per_published_listings
  	/ coalesce(nullif(count(1) over (partition by f.id_imovel),0),1)
  as vl_cost_marketing_ads,

  0::DECIMAL(14,4) as vl_cost_marketing_sms,

  -- ratear custo do mes, por dia pelos agendamentos que geraram contrato
  ac.cost_agents_comission
  -- 	/ coalesce(nullif(count(1) over (partition by f.id_scheduling),0),1)
  as vl_cost_agents_comission,

  -- ratear custo do mes de cada agente,
  -- ratear por regiao e rateia pelos agendamentos dos imoveis da regiao
  acs.agent_comission_per_slot::DECIMAL(14,4)
  --	/ coalesce(nullif(count(1) over (partition by f.id_imovel),0),1)
  as vl_cost_agents_slot,

  -- ratear custo do mes, por dia pelos imoveis que tiveram agendamento
  v.cost_visit
  	/ coalesce(nullif(count(1) over (partition by f.id_scheduling),0),1)
  as vl_cost_visit_support,

  -- ratear custo do mes, por dia 'pelos imoveis que tiveram contrato
  c.cost_closing_support ::DECIMAL(14,4)
  as vl_cost_closing_support,

  -- ratear custo do dia pelos imoveis publicados no dia determinado
  cc.classified_cost::DECIMAL(14,4)
  --	/ coalesce(nullif(count(1) over (partition by f.id_imovel),0),1)
   as vl_cost_classifieds,

  now()::timestamp as dt_timestamp

from
  property_scheduling f

left join booking b
  on b.id = f.id_scheduling
  
left join
	vw_property_listing p
	on p.id = f.id_imovel
	and coalesce(b."criadoEm", '1901-01-01') between coalesce(p.min_version_time, '1900-01-01') and coalesce(p.max_version_time, now()) 
	
/*
left join lateral
(
  select
  	esv.imovel_id,
    esv.initial_utm_source,
    esv.initial_utm_medium,
    esv.initial_utm_campaign,
    esv.initial_referring_domain,
    esv.utm_source,
    esv.utm_medium,
    esv.utm_campaign,
    esv.referring_domain
  from
    amplitude_event_schedule_visit esv
  where
  	esv.imovel_id = f.id_imovel
    and esv.event_time::timestamp <= coalesce(b."criadoEm", '2999-01-01')
  order by
  	esv.event_time desc
  limit 1
) esv
  on true
*/

left join
  vw_imovel_liquidity_marketing_costs h
  on f.id_imovel = h.id
  and p.version = h.version

left join
  vw_imovel_liquidity_agents_costs ac
  on coalesce(f.id_scheduling, -1) = coalesce(ac.id_scheduling, -1)
  and coalesce(f.id_imovel, -1) = coalesce(ac.id_imovel, -1)
  and coalesce(f.id_contract, -1) = coalesce(ac.id_contract, -1)

left join
  vw_imovel_liquidity_closing_costs c
  on coalesce(f.id_scheduling, -1) = coalesce(c.id_scheduling, -1)
  and coalesce(f.id_imovel, -1) = coalesce(c.id_imovel, -1)
  and coalesce(f.id_contract, -1) = coalesce(c.id_contract, -1)

left join
  vw_imovel_liquidity_visit_costs v
  on coalesce(f.id_scheduling, -1) = coalesce(v.id_scheduling, -1)
  and coalesce(f.id_imovel, -1) = coalesce(v.id_imovel, -1)
  and coalesce(f.id_visit, -1) = coalesce(v.id_visit, -1)
  and coalesce(f.id_pre_proposal, -1) = coalesce(v.id_pre_proposal, -1)
  and coalesce(f.id_proposal, -1) = coalesce(v.id_proposal, -1)
  and coalesce(f.id_contract, -1) = coalesce(v.id_contract, -1)

left join
(
  select
  	id_property,
    version,
    sum(comission_per_slot) as agent_comission_per_slot
  from
  	vw_imovel_agent_comission_slot s
  group by
  	id_property,
    version
) acs
on acs.id_property = f.id_imovel -- 892792831
and acs.version = p.version

left join
(
  select
	id,
    version,
    sum(classified_cost) as classified_cost
  from
  	vw_imovel_liquidity_classifieds_costs
  group by
	id,
    version
) cc
on cc.id = f.id_imovel
and cc.version = p.version
;