with leads_3p as(
  SELECT
    fl.sk_broker
    ,fl.sk_lead_3p
    ,fl.sk_house
    ,fl.sk_region
    ,max(case when business_context = 'RENT' then 'RENT' end) as business_context_rent
    ,max(case when business_context = 'SALE' then 'SALE' end) as business_context_sale
    ,max(case when business_context = 'RENT' then date(fl.ts_business_context_created) end) AS dt_lead
    ,max(case when business_context = 'RENT' then date(fl.ts_lead_created) end) as dt_lead_created
    ,max(case when business_context = 'RENT' then date(fl.ts_first_listing) end) as dt_first_listing
  FROM dw_3p_supply.fact_lead_3p_flows fl
  WHERE fl.business_context in('RENT','SALE')
  and fl.sk_house <> -1
  and date(fl.ts_first_listing) is not null

  group by
    fl.sk_broker
    ,fl.sk_lead_3p
    ,fl.sk_house
    ,fl.sk_region

)
, sk_house_rent as(
  select 
    l3.sk_broker
    ,l3.sk_lead_3p
    ,l3.sk_house
    ,l3.sk_region
    ,l3.business_context_rent
    ,l3.business_context_sale
    ,l3.dt_lead
    ,l3.dt_lead_created
    ,l3.dt_first_listing
    ,CASE
      --- flagamos tudo que é 3P, tudo que é REDE e 3P (classifica todos os sk-house que são 3P)
          WHEN obt.nm_supply_source = '3P' THEN TRUE
          WHEN UPPER(obt.planning_conversion) = 'REDE' THEN TRUE
          ELSE FALSE
      END AS is_3p_fr_test
    ,CASE
      --- Aqui é uma quebra do que é OPs (era cadastro manual via magic link) migrou em fevereiro ou março foi migrado para o supply processor (isso é um regra antiga) na migração o created-context foi no dia que fizeram essa migração. 
          WHEN obt.nm_supply_source = '3P'
          AND UPPER(obt.planning_conversion) <> 'REDE' THEN TRUE
          ELSE FALSE
      END AS is_ops
    ,CASE
      --- flag para classificar quem é organico
          WHEN UPPER(obt.planning_conversion) = 'REDE'
          AND l3.sk_lead_3p IS NULL THEN TRUE
          WHEN UPPER(obt.planning_conversion) = 'REDE'
          AND l3.sk_lead_3p IS NOT NULL
          AND l3.dt_lead < DATE '2026-02-19' THEN TRUE
          ELSE FALSE
      END AS is_organic
    ,CASE
      --- flag para ver se subiu via supply processor
          WHEN UPPER(obt.planning_conversion) = 'REDE'
          AND l3.sk_lead_3p IS NOT NULL
          AND l3.dt_lead >= DATE '2026-02-19' THEN TRUE
          ELSE FALSE
      END AS is_bsp
    ,CASE WHEN business_context_sale = 'SALE' AND nm_business_context = 'RENT' THEN TRUE ELSE FALSE END is_organic_new
  from leads_3p l3

  inner join dw_growth.obt_supply obt
    on l3.sk_house = obt.sk_house

  where true 
  and obt.nm_supply_source = '3P'
  and obt.nm_business_context = 'RENT'
  and obt.cd_funnel_step = 'first_listing'

)
, rent_events_coincident as(
  select

    de.sk_event
    ,de.sk_booking
    ,de.sk_offer
    ,de.sk_contract
    ,de.sk_visit
    ,de.sk_house
    ,de.sk_agent
    ,de.sk_event_date
    ,de.sk_event_type
    ,et.abbreviation
    ,lr.is_organic
    ,lr.is_ops
    ,lr.is_3p_fr_test
    ,lr.is_organic
    ,lr.is_bsp

    ,dd.date
    
    ,lr.sk_broker

  from dw_rent.fact_rent_demand_events de

  inner join dw_rent.dim_rent_event_type et
    on de.sk_event_type = et.sk_event_type

  inner join dw_public.dim_date dd
    on de.sk_event_date = dd.sk_date

  inner join sk_house_rent lr
    on de.sk_house = lr.sk_house

  where true 
  and de.sk_event_date >= 20260101
  and de.sk_event_date < CAST(date_format(current_date(), 'yyyyMMdd') AS INT)

)
, agg_events as(
  select 
    ec.sk_broker
    ,cb.broker_trade_name_tag
    ,cb.city_group as city_group_broker
    ,cb.account_manager
    ,ec.sk_agent
    ,ec.sk_booking
    ,ec.sk_house
    ,ec.is_organic
    ,ec.is_ops
    ,ec.is_3p_fr_test
    ,ec.is_organic
    ,ec.is_bsp
    ,'supply' as business_model
    ,ec.date
    
    ,count(distinct case when ec.abbreviation = 'VB' then ec.sk_event end) as visit_booked
    ,count(distinct case when ec.abbreviation = 'VC' then ec.sk_event end) as visit_completed
    ,count(distinct case when ec.abbreviation = 'OS' then ec.sk_event end) as offer_sent
    ,count(distinct case when ec.abbreviation = 'OR' then ec.sk_event end) as offer_rejected
    ,count(distinct case when ec.abbreviation = 'OA' then ec.sk_event end) as offer_accepted
    ,count(distinct case when ec.abbreviation = 'CA' then ec.sk_event end) as credit_approved
    ,count(distinct case when ec.abbreviation = 'CS' then ec.sk_event end) as contract_signed

  from rent_events_coincident ec

  inner join sandbox.dim_brokers_3p cb
    on ec.sk_broker = cb.sk_broker

  group by
    ec.sk_broker
    ,cb.broker_trade_name_tag
    ,cb.city_group
    ,cb.account_manager
    ,ec.sk_agent
    ,ec.sk_booking
    ,ec.sk_house
    ,ec.is_organic
    ,ec.is_ops
    ,ec.is_3p_fr_test
    ,ec.is_organic
    ,ec.is_bsp
    ,'supply'
    ,ec.date

)
select 
  sk_broker	
  ,broker_trade_name_tag
  ,city_group_broker
  ,account_manager
  ,sk_agent
  ,sk_booking
  ,sk_house	
  ,is_organic
  ,is_ops
  ,is_3p_fr_test
  ,is_bsp
  ,business_model	
  ,date	
  ,visit_booked	
  ,visit_completed	
  ,offer_sent	
  ,offer_accepted	
  ,credit_approved	
  ,contract_signed

from agg_events
