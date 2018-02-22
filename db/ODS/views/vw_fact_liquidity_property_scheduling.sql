drop view if exists vw_fact_liquidity_property_scheduling;
create view vw_fact_liquidity_property_scheduling as
with fact as (
    select
      f.id_property_scheduling as ods_id,
      -- coalesce(f.id_imovel, -1) as sk_property,
      coalesce((f.id_imovel || lpad(coalesce(p."version"::varchar(3), '1'), 3, '0'))::bigint, -1::bigint) as sk_property,
      coalesce(i.regiao_id, -1)as sk_region,
      p."version"::integer as listing_number,
      coalesce(b.id, -1) as sk_booking,
      coalesce(id_owner, -1) as sk_owner,
      coalesce(id_user_affiliate, -1) as sk_user_affiliate,
      coalesce(f.id_user_agent, -1) as sk_user_agent,
      coalesce(f.id_user_visitor, -1) as sk_user_visitor,
      coalesce(f.id_user_visit_agent, -1) as sk_user_visit_agent,
      coalesce(f.id_visit, -1) as sk_visit,
      coalesce(f.id_negotiation, -1) as sk_negotiation,
      case
        when f.id_offer > 0
            then (f.id_offer * 100) + 2
        when f.id_pre_proposal > 0
            then (f.id_pre_proposal * 100) + 1
        else -1
      end as sk_offer,
      coalesce(f.id_proposal, -1) as sk_proposal,
      coalesce(f.id_contract, -1) as sk_contract,
      coalesce(f.id_rental_flow, -1) as id_rental_flow,

  coalesce(to_char(p.first_publication_date,'YYYYMMDD')::integer, -1) as sk_first_listing_date,
  coalesce(to_char(p.min_version_time,'YYYYMMDD')::integer, -1) as sk_listing_date,
  coalesce(to_char(b."criadoEm",'YYYYMMDD')::integer, -1) as sk_booking_created_date,
  coalesce(to_char(b.data,'YYYYMMDD')::integer, -1) as sk_visit_date,
  coalesce(to_char(visitor.criado_em,'YYYYMMDD')::integer, -1) as sk_visitor_user_signup_date,
  coalesce(to_char(coalesce(offer.criado_em, pp."criadoEm"),'YYYYMMDD')::integer, -1) as sk_offer_created_date,
  coalesce(to_char(contract."dataAssinado",'YYYYMMDD')::integer, -1) as sk_contract_signed_date,
  coalesce(to_char(agent.criado_em,'YYYYMMDD')::integer, -1) as sk_user_agent_date,

  dt_contract_anullment,
  visit_created_from_app,
  visit_created_type,
  visit_last_updated_from_app,
  visit_last_updated_type,

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
  	/ coalesce(nullif(count(1) over (partition by f.id_imovel, p."version"),0),1)
  as vl_cost_marketing_campaigns,

  h.vl_cost_marketing_ads_per_published_listings
  	/ coalesce(nullif(count(1) over (partition by f.id_imovel, p."version"),0),1)
  as vl_cost_marketing_ads,

  0::DECIMAL(14,4) as vl_cost_marketing_sms,

  -- ratear custo do mes, por dia pelos agendamentos que geraram contrato
  ac.cost_agents_comission
   	/ coalesce(nullif(count(1) over (partition by f.id_scheduling),0),1)
  as vl_cost_agents_comission,

  -- ratear custo do mes de cada agente,
  -- ratear por regiao e rateia pelos agendamentos dos imoveis da regiao
  acs.agent_comission_per_slot::DECIMAL(14,4)
  	/ coalesce(nullif(count(1) over (partition by f.id_imovel, p."version"),0),1)
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
  	/ coalesce(nullif(count(1) over (partition by f.id_imovel, p."version"),0),1)
   as vl_cost_classifieds,

  now()::timestamp as dt_timestamp

from
  property_scheduling f

left join booking b
  on b.id = f.id_scheduling

left join
  property_listing p
  on p.id = f.id_imovel
  and coalesce(b."criadoEm", '1901-01-01') between coalesce(p.min_version_time, '1900-01-01') and coalesce(p.max_version_time, now())

left join
  usuario visitor
  on visitor.id = f.id_user_visitor

left join
  usuario agent
  on agent.id = f.id_user_visit_agent

left join
  offer
  on offer.id = f.id_offer

left join
  pre_proposal pp
  on pp.id = f.id_pre_proposal

left join
  contract
  on contract.id = f.id_contract

left join
  imovel i
  on i.id = b.imovel_id

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
  on c.id_property_scheduling = f.id_property_scheduling

left join
  vw_imovel_liquidity_visit_costs v
  on coalesce(f.id_scheduling, -1) = coalesce(v.id_scheduling, -1)
  and coalesce(f.id_imovel, -1) = coalesce(v.id_imovel, -1)
  and coalesce(f.id_visit, -1) = coalesce(v.id_visit, -1)
  and coalesce(f.id_offer, f.id_pre_proposal, -1) = coalesce(v.id_offer, v.id_pre_proposal, -1)
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
),
calculated_dates as (
    select
        f.*,
        dof.dt_first_sent as offer_date,
        case
          when dof.status in ('Rejeitada', 'Aprovada')
              then dof.dt_updated
          else null::timestamp
        end as internal_analysis_date,
        dof.dt_approved as offer_approved_date,
        dpr.dt_credit_analysis_init as credit_analysis_init_date,
        case
          when dpr.status in ('Rejeitada', 'Aprovada')
           then dpr.dt_updated
          else null::timestamp
        end as credit_analysis_date,
        dpr.dt_proposal_approved as credit_analysis_approved_date,
        case
          when dct.contract_status in ('Cancelado', 'Finalizado')
              then dct.dt_updated
          else dct.dt_signature
        end as contract_date,
        dbo.dt_booking as visit_date,
        dbo.dt_created as booking_date
    from fact f
    left join vw_dim_offer dof
        on f.sk_offer = dof.sk_offer
    left join vw_dim_proposal dpr
        on f.sk_proposal = dpr.sk_proposal
    left join vw_dim_contract dct
        on f.sk_contract = dct.sk_contract
    left join vw_dim_booking dbo
        on f.sk_booking = dbo.sk_booking
)
select
  ods_id,
  sk_property,
  sk_region,
  listing_number,
  sk_booking,
  sk_owner,
  sk_user_affiliate,
  sk_user_agent,
  sk_user_visitor,
  sk_user_visit_agent,
  sk_visit,
  sk_negotiation,
  sk_offer,
  sk_proposal,
  sk_contract,
  id_rental_flow,
  sk_first_listing_date,
  sk_listing_date,
  sk_booking_created_date,
  sk_visit_date,
  sk_visitor_user_signup_date,
  sk_offer_created_date,
  sk_contract_signed_date,
  sk_user_agent_date,
  dt_contract_anullment,
  visit_created_from_app,
  visit_created_type,
  visit_last_updated_from_app,
  visit_last_updated_type,
  initial_source,
  initial_medium,
  initial_campaign,
  initial_referring_domain,
  source,
  medium,
  campaign,
  referring_domain,
  vl_cost_marketing_campaigns,
  vl_cost_marketing_ads,
  vl_cost_marketing_sms,
  vl_cost_agents_comission,
  vl_cost_agents_slot,
  vl_cost_visit_support,
  vl_cost_closing_support,
  vl_cost_classifieds,
  dt_timestamp,
  (date_part('day', visit_date - booking_date) * 24 +
              date_part('hour', visit_date - booking_date)) / 24.0 as booking_to_visit,
  (date_part('day', internal_analysis_date - offer_date) * 24 +
              date_part('hour', internal_analysis_date - offer_date)) / 24.0 as offer_to_internal_analyis,
  (date_part('day', credit_analysis_init_date - offer_approved_date) * 24 +
              date_part('hour', credit_analysis_init_date - offer_approved_date)) / 24.0 as offer_to_credit_analysis_init_date,
  (date_part('day', credit_analysis_approved_date - credit_analysis_init_date) * 24 +
              date_part('hour', credit_analysis_approved_date - credit_analysis_init_date)) / 24.0 as credit_analysis_init_to_end,
  (date_part('day', contract_date - credit_analysis_approved_date) * 24 +
              date_part('hour', contract_date - credit_analysis_approved_date)) / 24.0 as credit_analysis_to_contract
from calculated_dates
;