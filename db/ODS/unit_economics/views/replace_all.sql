drop view if exists unit_economics.vw_base_property_costs cascade;
drop view if exists unit_economics.vw_base_contract_costs cascade;
drop view if exists unit_economics.vw_base_dre_costs cascade;
drop view if exists unit_economics.vw_base_ticket_task cascade;
drop view if exists unit_economics.vw_supply_ops_inside_sales_costs cascade;
drop view if exists unit_economics.vw_supply_ops_photos_costs cascade;
drop view if exists unit_economics.vw_supply_ops_costs cascade;
drop view if exists unit_economics.vw_supply_mkt_affiliate_campaigns_costs cascade;
drop view if exists unit_economics.vw_supply_mkt_owner_campaigns_costs cascade;
drop view if exists unit_economics.vw_supply_mkt_costs cascade;
drop view if exists unit_economics.vw_supply_affiliate_bonus_costs cascade;
drop view if exists unit_economics.vw_supply_costs cascade;
drop view if exists unit_economics.vw_net_revenue_affiliate_commission_costs cascade;
drop view if exists unit_economics.vw_net_revenue_commission_costs cascade;
drop view if exists unit_economics.vw_net_revenue_revenues cascade;
drop view if exists unit_economics.vw_net_revenue_revenues_brokerage_fee cascade;
drop view if exists unit_economics.vw_net_revenue_revenues_mgmt_fee cascade;
drop view if exists unit_economics.vw_net_revenue_agent_commission_costs cascade;
drop view if exists unit_economics.vw_net_revenue_revenues_brokerage_plus_mgmt_aux cascade;
drop view if exists unit_economics.vw_net_revenue_taxes_sales_tax_iss cascade;
drop view if exists unit_economics.vw_net_revenue_taxes_sales_tax_pis_cofins cascade;
drop view if exists unit_economics.vw_net_revenue_taxes_delay_fine cascade;
drop view if exists unit_economics.vw_net_revenue_taxes cascade;
drop view if exists unit_economics.vw_net_revenue_costs cascade;
drop view if exists unit_economics.vw_mgmt_ops_bo_offboarding_costs cascade;
drop view if exists unit_economics.vw_mgmt_ops_bo_onboarding_costs cascade;
drop view if exists unit_economics.vw_mgmt_ops_bo_ongoing_costs cascade;
drop view if exists unit_economics.vw_mgmt_ops_collection_costs cascade;
drop view if exists unit_economics.vw_mgmt_ops_cs_post_sale_costs cascade;
drop view if exists unit_economics.vw_mgmt_ops_inspection_costs;
drop view if exists unit_economics.vw_mgmt_ops_costs cascade;
drop view if exists unit_economics.vw_mgmt_insurance_fee cascade;
drop view if exists unit_economics.vw_mgmt_insurance_pis_cofins;
drop view if exists unit_economics.vw_mgmt_insurance;
drop view if exists unit_economics.vw_mgmt_costs cascade;
drop view if exists unit_economics.vw_liquidity_mkt_tenant_campaigns_costs cascade;
drop view if exists unit_economics.vw_liquidity_ops_bo_pre_sale_costs cascade;
drop view if exists unit_economics.vw_liquidity_mkt_costs cascade;
drop view if exists unit_economics.vw_liquidity_ops_cs_pre_sale_costs cascade;
drop view if exists unit_economics.vw_liquidity_ops_field_ops_costs cascade;
drop view if exists unit_economics.vw_liquidity_ops_costs cascade;
drop view if exists unit_economics.vw_liquidity_lockbox_costs cascade;
drop view if exists unit_economics.vw_liquidity_ab_agent_hours_costs cascade;
drop view if exists unit_economics.vw_liquidity_costs cascade;
drop view if exists unit_economics.vw_fact_property_economics cascade;

create or replace view unit_economics.vw_base_property_costs as
select
  ((id || '00') || coalesce(version, 1))::bigint as sk_property,
  id as property_id,
  version,
  min_version_time as publication_date,
  status,
  min_version_time,
  coalesce(max_version_time, '2300-01-01')::date as max_version_time
from public.vw_property_listing
;

create or replace view unit_economics.vw_base_contract_costs as
select
  id,
  imovel_id as property_id,
  status,
  "valorAluguel" as rent_value,
  ("valorCondominio" + "valorAluguel") as package_value,
  "dataRescisao" as termination_date,
  "dataInicio" + interval '44 months' as expected_end_date,
  "dataAssinado" as signature_date,
  "dataEntrada" as entrance_date,
  "dataInicio" as init_date,
  "criadoEm" as created_date
from contract
where tipo = 'FullService'
    and status in ('Finalizado', 'Ativo')
    and date_trunc('month', "dataAssinado") >= '2016-01-01'
    and date_trunc('month', "dataEntrada") >= '2016-01-01'
    and date_trunc('month', "dataInicio") >= '2016-01-01'
;

create or replace view unit_economics.vw_base_dre_costs as
select
  "Value" as dre_value,
  "Month"::date as dre_date,
  "Category" as dre_category
from files.costs_dre
where "Value" != 0
;

create view unit_economics.vw_base_ticket_task as
with zendesk_groups as (
  select distinct
    id,
    case
      when trim("name") ~* '(adm financeiro)|(adm casos)|(adm media..es)|(cx p.s)|(cx adm)'
        then 'Customer Support (post-sale)'
      when trim("name") ~* '(comercial e afiliados)|(cx pr.)|(cx pr. missed chat)|(supporte)|(whatsapp)|(suporte$)|(closing)|(cx an.)'
        then 'Customer Support (pre-sale)'
      when trim("name") ~* '(adm offboarding)|(adm rescis.o)'
        then 'Back-Office (offboarding)'
      when trim("name") ~* '(adm onboarding)'
        then 'Back-Office (onboarding)'
      when trim("name") ~* 'collections'
        then 'Collection'
      else lower(trim("name"))
    end as group_name
  from zendesk."group"
),
zendesk_ticket_fields as (
  select
    ticket_id,
    case
      when value ~* '0+' or value is null
        then '-1'
      else value
    end as value
  from zendesk.ticket_fields
  where id = '31646438' -- field id that maps a house id
),
zendesk_cte as (
  select distinct
    case
  	    when ztf.value = '-1' or ztf.value is null
  		    then coalesce(vbmu0.property_id::varchar, vbmu1.property_id::varchar, '-1')
        else ztf.value
    end as property_id,
    case
        when vbmu0.property_id is not null
        	then count(vbmu0.property_id)
        when vbmu1.property_id is not null
        	then count(vbmu1.property_id)
    	else count(ztf.value)
    end as qt,
    date_trunc('month', ztm.solved_at)::date as dt,
    zg.group_name
  from zendesk.ticket zt
    join zendesk_groups zg
      on zt.group_id = zg.id
    join zendesk.ticket_metrics ztm
      on zt.id = ztm.ticket_id
         and ztm.solved_at is not null
    left join zendesk_ticket_fields ztf
      on zt.id = ztf.ticket_id
    left join zendesk.user zu
      on zt.requester_id = zu.id
    left join unit_economics.vw_base_merged_users vbmu0
      on zu.email = vbmu0.email
    left join unit_economics.vw_base_merged_users vbmu1
      on regexp_replace(zu.phone, '^\+\d{2}|\D', '', 'g') = vbmu1.phone
  where zg.group_name in ('Customer Support (pre-sale)', 'Customer Support (post-sale)', 'Collection',
                            'Back-Office (onboarding)', 'Back-Office (offboarding)')
  group by ztf.value, vbmu0.property_id, vbmu1.property_id, zg.group_name, date_trunc('month', ztm.solved_at)::date
),
crm_tasks as (
  select
    coalesce(property_id::varchar, '-1') as property_id,
    date_trunc('month', performed_date)::date as performed_date,
    case
      when trim(workgroup_title) ~* ('ap.lices')
        then 'ongoing'
      when trim(workgroup_title) ~* ('(backstage)|(laudo vistoria)|(onboarding rental)')
        then 'Back-Office (onboarding)'
      when trim(workgroup_title) ~* ('(capta..o$)|(capta..o priorit.ria)')
        then 'inside sales'
      when trim(workgroup_title) ~* ('(confirma..o de visitas)|(confirmar sess.o de fotos)|(vistoria)|(lockbox)|(onboar.ing de visitas)')
        then 'field ops'
      when trim(workgroup_title) ~* ('(cr.dito)')
        then 'analise de credito'
      when trim(workgroup_title) ~* ('(minuta)|(negocia..o)')
        then 'closing'
      else lower(trim(workgroup_title))
    end as group_name
  from crm.tasks
  where workgroup_title is not null
  and performed_date is not null
),
crm_cte as (
  select
    property_id,
    count(property_id) as qt,
    performed_date as dt,
    group_name
  from crm_tasks
  where group_name = 'Back-Office (onboarding)'
  group by property_id, performed_date, group_name
),
result as (
  select
    coalesce(zendesk_cte.property_id, crm_cte.property_id) as property_id,
    coalesce(zendesk_cte.dt, crm_cte.dt) as dt,
    coalesce(zendesk_cte.qt, 0) + coalesce(crm_cte.qt, 0) as qt,
    coalesce(zendesk_cte.group_name, crm_cte.group_name) as group_name
  from zendesk_cte
  full outer join crm_cte
    on zendesk_cte.property_id = crm_cte.property_id
       and zendesk_cte.dt = crm_cte.dt
       and zendesk_cte.group_name = crm_cte.group_name
),
final_result as (
  select
    case
      when length(property_id) in (5,6)
        then 892700000 + property_id::integer
      when length(property_id) > 9 or property_id !~ '^8927'
        then -1
      else property_id::integer
    end as property_id,
    dt,
    qt,
    group_name
  from result
)
select
  property_id,
  dt,
  sum(qt) as qt,
  group_name
from final_result
group by property_id, dt, group_name
;

create or replace view unit_economics.vw_supply_ops_inside_sales_costs as
with cdre_inside_sales as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category in ('Inside Sales', 'Inside sales')
),
filtered_properties as (
	select distinct
	    sk_property,
	    property_id,
	    min_version_time::date as listing_date
	from
		unit_economics.vw_base_property_costs base
	left join
		lead_conversion cl
		on cl.imovel_id = base.property_id
	where
		cl.id is not null
		and version = 1
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      fp.listing_date,
      cis.dre_date as dt_cash_flow,
      cis.dre_value / (count(fp.property_id) over (partition by cis.dre_date))::double precision as vl_inside_sales
    from filtered_properties fp
    join cdre_inside_sales cis
      on cis.dre_date = date_trunc('month', fp.listing_date) + interval '1 month'
)
select
  sk_property,
  property_id,
  dt_cash_flow as dt_cash_flow,
  vl_inside_sales
from costs c
;

create or replace view unit_economics.vw_supply_ops_photos_costs as
with cdre_photos as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Listing Photos'
),
filtered_properties as (
   select distinct
      sk_property,
      property_id,
      min_version_time::date as listing_date
    from unit_economics.vw_base_property_costs
    where version = 1
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      fp.listing_date,
      cp.dre_date as dt_cash_flow,
      cp.dre_value / (count(fp.property_id) over (partition by cp.dre_date))::double precision as vl_photos
    from filtered_properties fp
    join cdre_photos cp
      on cp.dre_date = date_trunc('month', fp.listing_date) + interval '1 month'
)
select
  sk_property,
  property_id,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 5) as dt_cash_flow,
  vl_photos
from costs
;

create or replace view unit_economics.vw_supply_ops_costs as
select
  coalesce(vsopc.sk_property, vsoisc.sk_property) as sk_property,
  coalesce(vsopc.property_id, vsoisc.property_id) as property_id,
  coalesce(vsopc.dt_cash_flow, vsoisc.dt_cash_flow) as dt_cash_flow,
  coalesce(vsopc.vl_photos, 0) as vl_photos,
  coalesce(vsoisc.vl_inside_sales, 0) as vl_inside_sales
from unit_economics.supply_ops_photos_costs vsopc
full outer join unit_economics.supply_ops_inside_sales_costs vsoisc
  on vsoisc.sk_property = vsopc.sk_property
     and vsoisc.dt_cash_flow = vsopc.dt_cash_flow
;

create or replace view unit_economics.vw_supply_mkt_affiliate_campaigns_costs as
-- Get Google Ads Supply Affiliate Per Year-Month
with google_monthly_affiliate_costs as (
	select
		date_part('month', "day"::date) as "month",
		date_part('year', "day"::date) as "year",
		sum((cost::DECIMAL(14,2)/1000000)::DECIMAL(14,2)) as cost
	from
		google_ads_campaigns
	where
		campaign like '%indicaai%'
	group by
		date_part('month', "day"::date),
		date_part('year', "day"::date)
),
-- Get Facebook Supply Affiliate Per Year-Month
facebook_monthly_affiliate_costs as
(
	select
        date_part('month', "date"::date) as "month",
        date_part('year', "date"::date) as "year",
        sum(spend::DECIMAL(14,2)) as cost
    from
        facebook_ads_campaigns
    where
        account_name = 'Supply'
    and
        (
            campaign_name like '%IA%'
            or campaign_name like '%indica%'
            or campaign_name like '%Indica%'
        ) is true
    group by
        date_part('month', "date"::date),
        date_part('year', "date"::date)
),
-- Join all costs into one single table
affiliate_mkt_costs as
(
	select
		coalesce(g."month", f."month") as month,
		coalesce(g."year", f."year") as year,
		(coalesce(g.cost, 0) + coalesce(f.cost, 0)) as cost
	from
		google_monthly_affiliate_costs g
	full outer join
		facebook_monthly_affiliate_costs f
	on g."year" = f."year" and f."month" = g."month"
),
affiliate_filtered_base as (
	select
		base.*,
		u.criado_em as affiliate_dt
	from
		unit_economics.vw_base_property_costs base
	left join
		potential_listings pl
		on pl.property_id = base.property_id
	left join
		lead l
		on pl.lead_id = l.id
	left join
		usuario u
		on u.id = l.usuario_que_indicou_id::int
	where
		pl.lead_id is not null
		and l.usuario_que_indicou_id is not null
		and l.tipo='Afiliado'
),
-- Divide all costs among versioned properties
divided_costs as (
	select
		sk_property,
		property_id,
		case
            when affiliate_dt < publication_date
            then publication_date::date
            else date_trunc('month', affiliate_dt + interval '2 month')::date
        end as dt_cash_flow,
		(coalesce(mkt.cost, 0)/count(1) over (
			partition by
			date_part('year', affiliate_dt),
			date_part('month', affiliate_dt)
		))::decimal(14,4) as vl_affiliate_campaigns
	from
		affiliate_filtered_base base
	left join
		affiliate_mkt_costs mkt
		on date_part('year', affiliate_dt) = mkt.year
		and date_part('month', affiliate_dt) = mkt.month
	-- filter by first version only, as is a supply cost
	where base.version = 1
)
select
	*
from
	divided_costs
where
	vl_affiliate_campaigns <> 0
;

create or replace view unit_economics.vw_supply_mkt_owner_campaigns_costs as
-- Get Google Ads Owner Costs Per Year-Month
with google_monthly_owner_costs as (
	select
		"day"::date as dt_cost,
		sum((cost::decimal(14,4)/1000000)::decimal(14,2)) as cost
	from
		google_ads_campaigns
	where
		(
			campaign like '%proprietarios%' or
			campaign like '%lp_quanto_cobrar%'
		)
	group by
		"day"::date
),
-- Get Facebook Owner Costs Per Year-Month
facebook_monthly_owner_costs as
(
	select
        "date"::date as dt_cost,
        sum(spend::decimal(14,4)) as cost
    from
        facebook_ads_campaigns
    where
        account_name = 'Supply'
    and
        (
            campaign_name like '%IA%'
            or campaign_name like '%indica%'
            or campaign_name like '%Indica%'
        ) is false
    group by
        "date"::date
),
-- Join all costs into one single table
owner_mkt_costs as
(
	select
		coalesce(g.dt_cost, f.dt_cost) as dt_cost,
		(coalesce(g.cost, 0) + coalesce(f.cost, 0)) as cost
	from
		google_monthly_owner_costs g
	full outer join
		facebook_monthly_owner_costs f
	on g.dt_cost = f.dt_cost
),
ten_day_base as
(
	select
		base.*,
		dt."date" as ten_pub_date
	from
		unit_economics.vw_base_property_costs base
	left join
		dim_date dt
		on dt."date" between base.publication_date - interval '10 day' and base.publication_date
	-- filter by first version only, as is a supply cost
	where base.version = 1
),
-- Divide all costs among versioned properties
divided_costs as (
	select
		sk_property,
		property_id,
		date_trunc('month', base.ten_pub_date + interval '2 month')::date as dt_cash_flow,
		(coalesce(mkt.cost, 0)/count(1) over (
			partition by
			base.ten_pub_date
		))::decimal(14,8) as vl_owner_campaigns
	from
		ten_day_base base
	left join
		owner_mkt_costs mkt
		on base.ten_pub_date = mkt.dt_cost
),
total as (
	-- Remove rows where costs equal zero
	select
		sk_property,
		property_id,
		dt_cash_flow,
		sum(vl_owner_campaigns)::decimal(14,8) as vl_owner_campaigns
	from
		divided_costs
	where
		vl_owner_campaigns <> 0
	group by
		sk_property,
		property_id,
		dt_cash_flow
)
select
	sk_property,
	property_id,
	dt_cash_flow,
	vl_owner_campaigns::decimal(14,4) as vl_owner_campaigns
from
	total
;

create or replace view unit_economics.vw_supply_mkt_costs as
select
	coalesce(affiliate.sk_property, owner.sk_property) as sk_property,
	coalesce(affiliate.property_id, owner.property_id) as property_id,
	coalesce(affiliate.dt_cash_flow, owner.dt_cash_flow) as dt_cash_flow,
	coalesce(vl_affiliate_campaigns, 0) as vl_affiliate_campaigns,
	coalesce(vl_owner_campaigns, 0) as vl_owner_campaigns
from
	unit_economics.supply_mkt_affiliate_campaigns_costs affiliate
full outer join
	unit_economics.supply_mkt_owner_campaigns_costs owner
	on affiliate.sk_property = owner.sk_property
	and affiliate.dt_cash_flow = owner.dt_cash_flow
;

create or replace view unit_economics.vw_supply_affiliate_bonus_costs as
with affiliate_filtered_base as (
	select
		base.*
	from
		unit_economics.vw_base_property_costs base
	left join
		potential_listings pl
		on pl.property_id = base.property_id
	left join
		lead l
		on pl.lead_id = l.id
	where
		pl.lead_id is not null
		and l.usuario_que_indicou_id is not null
		and l.tipo='Afiliado'
)
select
	base.sk_property,
	property_id,
	payment_date::date as dt_cash_flow,
	valor as vl_affiliate_bonus
from
	affiliate_filtered_base base
left join
	affiliate_payments ap
	on ap.imovel_id::integer = base.property_id
where
	base.version = 1
and
	tipo='valorFixoPorIndicacaoDeImovel'
;

create or replace view unit_economics.vw_supply_costs as
select
	coalesce(vsmc.sk_property, vsoc.sk_property, vsacc.sk_property) as sk_property,
	coalesce(vsmc.property_id, vsoc.property_id, vsacc.property_id) as property_id,
	coalesce(
    date_trunc('month', vsmc.dt_cash_flow)::date,
    date_trunc('month', vsoc.dt_cash_flow)::date,
    date_trunc('month', vsacc.dt_cash_flow)::date) as dt_cash_flow,
	coalesce(vsmc.vl_affiliate_campaigns, 0) as vl_affiliate_campaigns,
	coalesce(vsmc.vl_owner_campaigns, 0) as vl_owner_campaigns,
	coalesce(vsoc.vl_photos, 0) as vl_photos,
	coalesce(vsoc.vl_inside_sales, 0) as vl_inside_sales,
	coalesce(vsacc.vl_affiliate_bonus, 0) as vl_affiliate_bonus
from
	unit_economics.supply_mkt_costs vsmc
full outer join unit_economics.supply_ops_costs vsoc
  	on vsmc.sk_property = vsoc.sk_property
	and vsmc.dt_cash_flow = vsoc.dt_cash_flow
full outer join unit_economics.supply_affiliate_bonus_costs vsacc
	on vsacc.sk_property = coalesce(vsoc.sk_property, vsmc.sk_property)
	and vsacc.dt_cash_flow = coalesce(vsoc.dt_cash_flow, vsmc.dt_cash_flow)
;

create or replace view unit_economics.vw_net_revenue_affiliate_commission_costs as
with affiliate_filtered_base as (
	select
		base.*
	from
		unit_economics.vw_base_property_costs base
	left join
		potential_listings pl
		on pl.property_id = base.property_id
	left join
		lead l
		on pl.lead_id = l.id
	where
		pl.lead_id is not null
		and l.usuario_que_indicou_id is not null
		and l.tipo='Afiliado'
)
select
	base.sk_property,
	property_id,
	payment_date::date as dt_cash_flow,
	valor as vl_affiliate_commission,
	0 as flg_expected_affiliate_commission
from
	affiliate_filtered_base base
left join
	affiliate_payments ap
	on ap.imovel_id::integer = base.property_id
where
	base.version = 1
and
	tipo='porcentagemPorIndicacaoDeImovel'
;

create or replace view unit_economics.vw_net_revenue_agent_commission_costs as
with agents as (
  select distinct
    comm.dt,
    comm.percentage,
    cont.property_id as cont_property_id,
    cont.rent,
    cont.contract_id,
    c.property_id as c_property_id,
    c.signature_date
  from files.finance_agents_contract cont
  join files.finance_agents_commission comm
    on cont.agent_name = comm.agent_name
       and date_trunc('month', cont.signature_date) = comm.dt
  left join unit_economics.vw_base_contract_costs c
    on c.id = cont.contract_id
  where cont.status = 'Ativo'
),
filtered_properties as (
  select
    dt,
    coalesce(c_property_id, 892700000 + cont_property_id) as property_id,
    sum(percentage * rent) as vl_agent_commission
  from agents
  group by dt, c_property_id, contract_id, cont_property_id
),
new_rule_contract as (
	select
		vbcc.property_id,
		vbcc.rent_value * 0.2 as vl_agent_commission,
		date_trunc('month', signature_date) as dt
	from
		unit_economics.vw_base_contract_costs vbcc
	left join
		unit_economics.vw_base_property_costs vbpc
		on vbcc.property_id = vbpc.property_id
		and vbcc.signature_date between vbpc.min_version_time and vbpc.max_version_time
	left join
		booking b
		on b.imovel_id = vbcc.property_id
		and b."data" between vbpc.min_version_time and vbpc.max_version_time
	where
		date_trunc('month', signature_date) >= '2017-09-01'
	group by
		vbcc.property_id,
		vbcc.rent_value,
		vbcc.signature_date,
		vbpc.min_version_time,
		vbpc.max_version_time
	having count(b.id) > 0
),
-- Agents Commission spreadsheet doesn't contain contracts before Feb-2016
all_contracts as (
  select
    c.property_id,
    -- '0.5' is the commission average of Jan-2016
    c.rent_value * 0.5 as vl_agent_commission,
    date_trunc('month', signature_date) as dt
  from unit_economics.vw_base_contract_costs c
  where date_trunc('month', signature_date) = '2016-01-01'
  union
  select
    property_id,
    vl_agent_commission,
    dt
  from filtered_properties
  where dt < '2017-09-01'
  union
  select
    property_id,
    vl_agent_commission,
    dt
  from new_rule_contract
),
updated_dates as (
  select
    property_id,
    vl_agent_commission,
    dt + interval '2 month' as dt
  from all_contracts
)
select
  vbpc.sk_property,
  ud.property_id,
  make_date(extract(year from ud.dt)::int, extract(month from ud.dt)::int, 7) as dt_cash_flow,
  ud.vl_agent_commission,
  1 as flg_expected_agent_commission
from updated_dates ud
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = ud.property_id
    and ud.dt between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view unit_economics.vw_net_revenue_commission_costs as
select
    coalesce(affiliate.sk_property, agent.sk_property) as sk_property,
    coalesce(affiliate.property_id, agent.property_id) as property_id,
    coalesce(affiliate.dt_cash_flow, agent.dt_cash_flow) as dt_cash_flow,
    coalesce(affiliate.vl_affiliate_commission, 0) as vl_affiliate_commission,
    coalesce(agent.vl_agent_commission, 0) as vl_agent_commission,
    coalesce(affiliate.flg_expected_affiliate_commission, 0) as flg_expected_affiliate_commission,
    coalesce(agent.flg_expected_agent_commission, 0) as flg_expected_agent_commission
from
    unit_economics.net_revenue_affiliate_commission_costs affiliate
full outer join unit_economics.net_revenue_agent_commission_costs agent
  on affiliate.sk_property = agent.sk_property
     and affiliate.dt_cash_flow = agent.dt_cash_flow
;

create or replace view unit_economics.vw_net_revenue_revenues_brokerage_fee as
with base_contract as (
select
	vbpc.sk_property,
	vbpc.property_id,
	vbcc.id as contract_id,
	vbcc.init_date,
	vbcc.rent_value,
	coalesce(vbcc.termination_date, vbcc.expected_end_date)::date as end_date
from
	unit_economics.vw_base_contract_costs vbcc
left join
	unit_economics.vw_base_property_costs vbpc
	on vbcc.property_id = vbpc.property_id
	and coalesce(vbcc.termination_date, vbcc.expected_end_date)::date between vbpc.min_version_time
	                                                                    and (vbpc.max_version_time + interval '1 day')
where (vbcc.termination_date is not null
  or vbcc.expected_end_date is not null)
  and vbcc.status in ('Ativo', 'Finalizado')
),
brokerage_fill as (
	select
		sk_property,
		property_id,
		bc.contract_id,
		case
			when i.landlord_status = 'paid'
				then amount::decimal(14,4)
			when i.contract_id is not null
				then 0
			when i.contract_id is null and bc.init_date >= '2017-01-01'
				then rent_value
			else 0
		end as vl_brokerage_fee,
		init_date,
		greatest(
			landlord_due_date,
			due_date,
			landlord_paid_date,
			init_date + interval '1 month'
		)::date as dt_cash_flow
	from
		base_contract bc
	left join
		invoice i
		on bc.contract_id = i.contract_id
	and
		item = 'TaxaCorretagem'
	and
		"from" = 'Proprietario'
	and
		"to" = 'Contrato'
)
select
	sk_property,
	property_id,
	vl_brokerage_fee,
	dt_cash_flow,
	0 as flg_expected_brokerage_fee
from
	brokerage_fill
where vl_brokerage_fee != 0
;

create or replace view unit_economics.vw_net_revenue_revenues_mgmt_fee as
with filtered_contracts as (
    select distinct
        property_id,
        id,
        init_date,
        package_value,
        rent_value,
        coalesce(termination_date, expected_end_date)::date as end_date,
        date_trunc('month', dd.date)::date + interval '6 day' as date_range
    from
        unit_economics.vw_base_contract_costs
    join dim_date dd
        on date_trunc('month', dd.date) between date_trunc('month', init_date)
            and date_trunc('month', coalesce(termination_date, expected_end_date)::date)
    where termination_date is not null
        or expected_end_date is not null
),
base_contract as (
	select
		base.*,
		c.id as contract_id,
		package_value,
		rent_value,
		date_trunc('month', c.init_date) as contract_init_date,
		date_trunc('month', c.end_date) as contract_end_date,
		c.date_range
	from
		unit_economics.vw_base_property_costs base
	left join
		filtered_contracts c
		on base.property_id = c.property_id
		and c.end_date between base.min_version_time and (base.max_version_time + interval '1 day')
),
incurred as (
    select
    	row_number() over (partition by sk_property, bc.contract_id order by bc.date_range) as rn,
        sk_property,
        property_id,
        bc.contract_id,
        bc.contract_init_date,
        bc.contract_end_date,
        bc.package_value,
        bc.rent_value,
        amount::decimal(14,4) as vl_management_fee,
        greatest(
        	landlord_due_date,
        	due_date,
        	landlord_paid_date
        	) as dt_cash_flow,
        bc.date_range
    from
        base_contract bc
    left join
        invoice i
        on bc.contract_id = i.contract_id
            and date_trunc('month', greatest(landlord_due_date, due_date, landlord_paid_date)) = bc.date_range
            and item = 'TaxaAdministracao'
            and landlord_status = 'paid'
            and "from" = 'Proprietario'
            and "to" = 'Contrato'
),
incurred_diff as (
    select
        sk_property,
        property_id,
        case
        	when (rn=1 and vl_management_fee is null)
        		then package_value*0.08
        		else vl_management_fee
        end as vl_management_fee,
        case
        	when (rn=1 and vl_management_fee is null)
        		then contract_init_date + interval '2 month' + interval '6 day'
        		else dt_cash_flow
        end as dt_cash_flow,
        date_range,
        contract_end_date,
        contract_init_date,
        rent_value,
        (extract(year from (contract_end_date - contract_init_date)) * 12
                + extract(month from (contract_end_date - contract_init_date))
                + (extract(days from (contract_end_date - contract_init_date)) / 30))::integer as date_diff
    from incurred
),
incurred_plus_dates as (
    select
        sk_property,
        property_id,
        vl_management_fee,
        dt_cash_flow,
        date_range,
        rent_value,
        max(dt_cash_flow) over (partition by sk_property) as max_dt_cash_flow
    from incurred_diff
),
value_fill as (
    select distinct
        sk_property,
        property_id,
        vl_management_fee,
        case
            when date_range > max_dt_cash_flow
                then date_range
            else dt_cash_flow
        end as dt_cash_flow,
        max_dt_cash_flow,
        rent_value,
        gap_fill(vl_management_fee) over (partition by sk_property order by dt_cash_flow asc) as gf
    from incurred_plus_dates
),
result as (
    select
        sk_property,
        property_id,
        dt_cash_flow,
        case
            when dt_cash_flow > max_dt_cash_flow and dt_cash_flow >= '2018-02-01'
                then coalesce(vl_management_fee, rent_value*0.08)
            when dt_cash_flow > max_dt_cash_flow
                then coalesce(vl_management_fee, gf)
            else vl_management_fee
        end as vl_management_fee,
        dt_cash_flow > max_dt_cash_flow and vl_management_fee is null as flg_expected_management_fee
    from value_fill
)
select
    sk_property,
    property_id,
    vl_management_fee,
    dt_cash_flow::date,
    flg_expected_management_fee::integer
from result
where vl_management_fee != 0
;



create or replace view unit_economics.vw_net_revenue_revenues_brokerage_plus_mgmt_aux as
select
    coalesce(br.sk_property, mg.sk_property) as sk_property,
    coalesce(br.property_id, mg.property_id) as property_id,
    coalesce(br.vl_brokerage_fee, 0) + coalesce(mg.vl_management_fee, 0) as brokerage_plus_mgmt,
    coalesce(br.dt_cash_flow, mg.dt_cash_flow) as dt_cash_flow,
    coalesce(mg.flg_expected_management_fee, 0) as flg_expected_management_fee,
    coalesce(br.flg_expected_brokerage_fee, 0) as flg_expected_brokerage_fee
  from unit_economics.net_revenue_revenues_brokerage_fee br
  full outer join unit_economics.net_revenue_revenues_mgmt_fee mg
    on br.sk_property = mg.sk_property
       and br.dt_cash_flow = mg.dt_cash_flow
  where br.vl_brokerage_fee > 0
    or mg.vl_management_fee > 0
;

create or replace view unit_economics.vw_net_revenue_revenues as
select
	coalesce(b_fee.sk_property, m_fee.sk_property) as sk_property,
	coalesce(b_fee.property_id, m_fee.property_id) as property_id,
	coalesce(date_trunc('month', b_fee.dt_cash_flow)::date, date_trunc('month', m_fee.dt_cash_flow)::date) as dt_cash_flow,
	coalesce(m_fee.vl_management_fee, 0) as vl_management_fee,
	coalesce(m_fee.flg_expected_management_fee, 0) as flg_expected_management_fee,
	coalesce(b_fee.flg_expected_brokerage_fee, 0) as flg_expected_brokerage_fee,
	coalesce(b_fee.vl_brokerage_fee, 0) as vl_brokerage_fee
from
	unit_economics.net_revenue_revenues_brokerage_fee b_fee
full outer join
	unit_economics.net_revenue_revenues_mgmt_fee m_fee
	on b_fee.sk_property = m_fee.sk_property
	and b_fee.dt_cash_flow = m_fee.dt_cash_flow
;




create or replace view unit_economics.vw_net_revenue_taxes_delay_fine as
with filtered_dates as (
	select distinct
		date_trunc('month', dd."date") as dt
	from
		dim_date dd
),
filtered_fines as (
	select
		contract_id,
		sum(fine) as fine,
		paid_date
	from invoice_fines
	where fine > 0
	group by
		contract_id,
		paid_date
),
filtered_contracts as (
	select distinct
		c.property_id,
		c.id,
		c.init_date,
		coalesce(c.termination_date, c.expected_end_date) as end_date
	from
		unit_economics.vw_base_contract_costs c
	join filtered_fines ff
    on ff.contract_id = c.id
),
contract_dates as (
	select
		fc.property_id as property_id,
		fc.id,
		fd.dt,
		row_number() over (partition by fc.id order by fd.dt) as rn,
		case when fd.dt > now() then 1 else 0 end as flg_expected
	from
		filtered_contracts fc
	left join
		filtered_dates fd
	on fd.dt between fc.init_date and fc.end_date
),
fines as (
  select
		case when flg_expected = 0 then coalesce(ff.fine,0) else ff.fine end as fine,
		coalesce(ff.paid_date::date, c.dt) as dt,
		c.property_id as property_id,
		c.id,
		avg(case when flg_expected = 0 then coalesce(ff.fine,0) else ff.fine end) filter (where flg_expected=0) over (partition by c.id) as av,
		rn,
		flg_expected
  from contract_dates c
  left join filtered_fines ff
    on ff.contract_id = c.id
    and date_trunc('month',ff.paid_date) = c.dt
)
select
    vbpc.sk_property,
  f.property_id,
	coalesce(fine, gap_fill(av) over (partition by id order by dt)) as vl_delay_fine,
  f.dt::date as dt_cash_flow,
  f.flg_expected::integer as flg_expected_delay_fine
from fines f
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = f.property_id
    and f.dt between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view unit_economics.vw_net_revenue_taxes_sales_tax_iss as
with iss as (
  select
    sk_property,
    property_id,
    0.05 * brokerage_plus_mgmt as vl_st_iss,
    dt_cash_flow + interval '1 month' as dt_cash_flow
  from unit_economics.net_revenue_revenues_brokerage_plus_mgmt_aux
)
select
  sk_property,
  property_id,
  vl_st_iss,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 25) as dt_cash_flow,
  1 as flg_expected_sales_tax_iss
from iss
;

create or replace view unit_economics.vw_net_revenue_taxes_sales_tax_pis_cofins as
with pis_cofins as (
    select
        sk_property,
        property_id,
        0.0925 * brokerage_plus_mgmt as vl_st_pis_cofins,
        dt_cash_flow + interval '1 month' as dt_cash_flow
    from unit_economics.net_revenue_revenues_brokerage_plus_mgmt_aux
)
select
  sk_property,
  property_id,
  vl_st_pis_cofins,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 10) as dt_cash_flow,
  1 as flg_expected_sales_tax_pis_cofins
from pis_cofins
;

create or replace view unit_economics.vw_net_revenue_taxes as
select
	sk_property,
	property_id,
	date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
	sum(vl_st_iss) as vl_st_iss,
	sum(vl_st_pis_cofins) as vl_st_pis_cofins,
	sum(vl_delay_fine) as vl_delay_fine,
	sum(flg_expected_sales_tax_iss) as flg_expected_sales_tax_iss,
	sum(flg_expected_sales_tax_pis_cofins) as flg_expected_sales_tax_pis_cofins,
	sum(flg_expected_delay_fine) as flg_expected_delay_fine
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_st_iss,
		0 as vl_st_pis_cofins,
		0 as vl_delay_fine,
		flg_expected_sales_tax_iss,
		0 as flg_expected_sales_tax_pis_cofins,
		0 as flg_expected_delay_fine
	from
		unit_economics.net_revenue_taxes_sales_tax_iss
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_st_iss,
		vl_st_pis_cofins,
		0 as vl_delay_fine,
		0 as flg_expected_sales_tax_iss,
		flg_expected_sales_tax_pis_cofins,
		0 as flg_expected_delay_fine
	from
		unit_economics.net_revenue_taxes_sales_tax_pis_cofins
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_st_iss,
		0 as vl_st_pis_cofins,
		vl_delay_fine,
		0 as flg_expected_sales_tax_iss,
		0 as flg_expected_sales_tax_pis_cofins,
		flg_expected_delay_fine
	from
		unit_economics.net_revenue_taxes_delay_fine
) tbl
group by sk_property, property_id, dt_cash_flow
;

create or replace view unit_economics.vw_net_revenue_costs as
select
	sk_property,
	property_id,
	date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
	sum(vl_affiliate_commission) as vl_affiliate_commission,
	sum(vl_management_fee) as vl_management_fee,
	sum(vl_brokerage_fee) as vl_brokerage_fee,
	sum(vl_agent_commission) as vl_agent_commission,
	sum(vl_st_iss) as vl_st_iss,
	sum(vl_st_pis_cofins) as vl_st_pis_cofins,
	sum(vl_delay_fine) as vl_delay_fine,
  sum(flg_expected_management_fee) as flg_expected_management_fee,
  sum(flg_expected_brokerage_fee) as flg_expected_brokerage_fee,
  sum(flg_expected_affiliate_commission) as flg_expected_affiliate_commission,
  sum(flg_expected_agent_commission) as flg_expected_agent_commission,
  sum(flg_expected_sales_tax_iss) as flg_expected_sales_tax_iss,
  sum(flg_expected_sales_tax_pis_cofins) as flg_expected_sales_tax_pis_cofins,
  sum(flg_expected_delay_fine) as flg_expected_delay_fine
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_affiliate_commission,
		0 as vl_management_fee,
		0 as vl_brokerage_fee,
		vl_agent_commission,
		0 as vl_st_iss,
		0 as vl_st_pis_cofins,
		0 as vl_delay_fine,
		0 as flg_expected_management_fee,
		0 as flg_expected_brokerage_fee,
		flg_expected_affiliate_commission,
		flg_expected_agent_commission,
		0 as flg_expected_sales_tax_iss,
		0 as flg_expected_sales_tax_pis_cofins,
		0 as flg_expected_delay_fine
	from
		unit_economics.net_revenue_commission_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_affiliate_commission,
		vl_management_fee,
		vl_brokerage_fee,
		0 as vl_agent_commission,
		0 as vl_st_iss,
		0 as vl_st_pis_cofins,
		0 as vl_delay_fine,
		flg_expected_management_fee,
		flg_expected_brokerage_fee,
		0 as flg_expected_affiliate_commission,
		0 as flg_expected_agent_commission,
		0 as flg_expected_sales_tax_iss,
		0 as flg_expected_sales_tax_pis_cofins,
		0 as flg_expected_delay_fine
	from
		unit_economics.net_revenue_revenues
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_affiliate_commission,
		0 as vl_management_fee,
		0 as vl_brokerage_fee,
		0 as vl_agent_commission,
		vl_st_iss,
		vl_st_pis_cofins,
		vl_delay_fine,
		0 as flg_expected_management_fee,
		0 as flg_expected_brokerage_fee,
		0 as flg_expected_affiliate_commission,
		0 as flg_expected_agent_commission,
		flg_expected_sales_tax_iss,
		flg_expected_sales_tax_pis_cofins,
		flg_expected_delay_fine
	from
		unit_economics.net_revenue_taxes
) tbl
group by sk_property, property_id, dt_cash_flow
;


create or replace view unit_economics.vw_mgmt_insurance_fee as
with payed_contracts as (
	select
		distinct
			c.id as contract_id,
			c.status,
			c.init_date as dt_start,
			coalesce(c.termination_date,c.expected_end_date) as dt_end,
			c.property_id as property_id,
			c.rent_value as rent
	from
		unit_economics.vw_base_contract_costs c
),
pay_dates as (
	select
		*,
		case
			when date_part('day', dt_start) > 20
			then (date_trunc('month', dt_start + interval '3 month') + interval '9 day')::date
			else (date_trunc('month', dt_start + interval '2 month') + interval '9 day')::date
		end as dt_first_pay,
		greatest(case
			when date_part('day', dt_start) > 20
			then (date_trunc('month', dt_start + interval '3 month') + interval '9 day')::date
			else (date_trunc('month', dt_start + interval '2 month') + interval '9 day')::date
		end,(date_trunc('month', dt_end + interval '1 month') + interval '9 day')::date) as dt_last_pay
	from
		payed_contracts
),
insurance_dates_prev as (
	select
		pd.contract_id,
		pd.property_id,
		dd."date" as dt_cash_flow,
		dt_start,
		rent,
		row_number() over (partition by pd.contract_id order by dd."date")-1 as rn
	from
		pay_dates pd
	left join
		dim_date dd
		on pd.dt_first_pay <= dd."date"
		and pd.dt_last_pay >= dd."date"
		and date_part('day', pd.dt_first_pay) = date_part('day', dd."date")
	where dd."date" is not null
	and rent is not null
),
insurance_dates as (
	select
		id.contract_id,
		id.property_id,
		id.dt_cash_flow,
		coalesce(
		case
			when (id1.dt_cash_flow < '2017-05-21') then id.rent * 0.0725
			when (id1.dt_cash_flow >= '2017-05-21' and id1.dt_cash_flow < '2018-02-01') then id.rent * 0.045
			else id.rent * 0.01
		end, 0
		) as insurance_fee,
		case
			when id1.dt_cash_flow < '2018-02-01' then 0
			else id.rent * 0.012
		end as default_fee,
		case
			when id.dt_cash_flow > now() then 1
			else 0
		end as flg_expected
	from insurance_dates_prev id
		left join insurance_dates_prev id1
		 on id.contract_id = id1.contract_id
		 and id1.rn % 12 = 0 and id.rn/12 = id1.rn/12
),
base_contract as (
	select
		base.*,
		c.contract_id
	from
		unit_economics.vw_base_property_costs base
	left join
		payed_contracts c
		on base.property_id = c.property_id
		and c.dt_end between base.min_version_time and base.max_version_time
)
select
	max(sk_property)::bigint as sk_property,
	bc.property_id,
	bc.contract_id,
	insurance_fee::decimal(14,4) as vl_insurance_fee,
	default_fee::decimal(14,4) as vl_default_fee,
	dt_cash_flow as dt_cash_flow,
	flg_expected
from
	base_contract bc
left join
	insurance_dates i
	on bc.contract_id = i.contract_id
where coalesce(insurance_fee, 0) > 0 or coalesce(default_fee, 0) > 0
group by
	bc.property_id,
	dt_cash_flow,
	vl_insurance_fee,
	vl_default_fee,
	bc.contract_id,
	flg_expected
;

create or replace view unit_economics.vw_mgmt_ops_bo_offboarding_costs as
with cdre_offboarding as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (offboarding)'
),
filtered_contracts as (
    select distinct
      property_id,
      id,
      date_trunc('month', coalesce(termination_date, expected_end_date)::date) as dt
    from unit_economics.vw_base_contract_costs
    where termination_date is not null
          or expected_end_date is not null
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Back-Office (offboarding)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.base_ticket_task tt
  where tt.group_name = 'Back-Office (offboarding)'
    and property_id != -1
),
ratio as (
  select distinct
    fc.dt,
    qn.qt / count(fc.property_id) over (partition by fc.dt) as qt
  from filtered_contracts fc
  left join qt_nulls qn
    on fc.dt = qn.dt
),
gen_contracts as (
	select
		fc.property_id,
		fc.dt,
		r.qt as qt_gen
	from
  	filtered_contracts fc
  left join ratio r
  	on fc.dt = r.dt
),
espec_gen_prev as (
  select
    fc.property_id,
    cqt.dt as dt,
    cqt.qt as qt
  from
  	filtered_contracts fc
  join calculated_qt cqt
    on cqt.property_id = fc.property_id
  union
  select
  	*
	from gen_contracts
),
espec_gen as (
	select
		property_id,
		dt,
		sum(qt) as qt
	from espec_gen_prev
	group by
		property_id, dt
),
tt_costs as (
    select
      eg.property_id,
      eg.dt,
      co.dre_date as dt_cash_flow,
      co.dre_value * eg.qt / (sum(eg.qt) over (partition by co.dre_date))::double precision as vl_bo_offboarding,
      (dre_value is null)::int as flg_expected
    from espec_gen eg
    join cdre_offboarding co
      on co.dre_date = eg.dt + interval '1 month'
)
,
contract_costs as (
    select
      fc.property_id,
      fc.dt,
      coalesce(co.dre_date, fc.dt) as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_offboarding,
      (dre_value is null)::int as flg_expected
    from filtered_contracts fc
    left join cdre_offboarding co
      on co.dre_date = fc.dt + interval '1 month'
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_bo_offboarding, cc.vl_bo_offboarding) as vl_bo_offboarding,
  	coalesce(tt.flg_expected, cc.flg_expected) as flg_expected
  from tt_costs tt
  full outer join contract_costs cc
    on tt.dt_cash_flow = cc.dt_cash_flow
),
last_3_avg as (
	select
		t1.dt,
		t1.property_id,
		t1.dt_cash_flow,
		t1.vl_bo_offboarding,
		t1.flg_expected,
		avg(t2.vl_bo_offboarding) as m_avg
	from full_costs t1
	join
		full_costs t2
		on t2.dt_cash_flow >= t1.dt_cash_flow - interval '3 month' and t2.dt_cash_flow <= t1.dt_cash_flow
	group by t1.dt, t1.property_id, t1.dt_cash_flow, t1.vl_bo_offboarding, t1.flg_expected
),
coalesced_values as (
	select
		coalesce(vbpc.sk_property, (lavg.property_id || '001')::bigint) as sk_property,
		lavg.property_id,
		lavg.dt_cash_flow::date,
		case
			when dt_cash_flow >= '2017-01-01'
			then coalesce(vl_bo_offboarding,max(m_avg) filter (where flg_expected = 0) over ())
			else coalesce(vl_bo_offboarding, 0)
		end as vl_bo_offboarding,
		flg_expected
	from last_3_avg lavg
	left join unit_economics.vw_base_property_costs vbpc
	  on vbpc.property_id = lavg.property_id
	    and lavg.dt between vbpc.min_version_time and vbpc.max_version_time
)
select
	*
from
	coalesced_values
where
	vl_bo_offboarding != 0
;

create or replace view unit_economics.vw_mgmt_ops_bo_onboarding_costs as
with cdre_onboarding as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (onboarding)'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Back-Office (onboarding)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.base_ticket_task tt
  where tt.group_name = 'Back-Office (onboarding)'
    and property_id != -1
),
filtered_contracts_prev as (
  select distinct
    property_id,
    case
      when signature_date::date > init_date::date
        then init_date::date
      else signature_date::date
    end as "from",
    case
      when signature_date::date > init_date::date
        then signature_date::date
      else init_date::date
    end as "to"
  from unit_economics.vw_base_contract_costs
  where signature_date is not null
    and init_date is not null
),
filtered_contracts as(
	select distinct
		fc.property_id,
		coalesce(dre.dre_date, date_trunc('month', fc."to") + interval '1 month') as dt
	from filtered_contracts_prev fc
	left join cdre_onboarding dre
		on dre.dre_date between date_trunc('month', fc."from") + interval '1 month'
                        and date_trunc('month', fc."to") + interval '1 month'
    where fc."from" >= '2015-12-01'
        and fc."to" >= '2015-12-01'
),
ratio as (
  select distinct
    fc.dt,
    qn.qt / count(fc.property_id) over (partition by fc.dt) as qt
  from filtered_contracts fc
  left join qt_nulls qn
    on fc.dt = qn.dt
),
gen_contracts as (
	select
		fc.property_id,
		fc.dt,
		r.qt as qt_gen
	from
  	filtered_contracts fc
  left join ratio r
  	on fc.dt = r.dt
),
espec_gen_prev as (
  select
    fc.property_id,
    coalesce(cqt.dt, fc.dt) as dt,
    cqt.qt as qt
  from
  	filtered_contracts fc
  join calculated_qt cqt
    on cqt.property_id = fc.property_id
  union
  select
  	*
    from gen_contracts
),
espec_gen as (
	select
		property_id,
		dt,
		sum(qt) as qt
	from espec_gen_prev
	group by
		property_id, dt
),
tt_costs as (
    select
      eg.property_id,
      eg.dt,
      eg.dt as dt_cash_flow,
      co.dre_value * eg.qt / (sum(eg.qt) over (partition by eg.dt))::double precision as vl_bo_onboarding
    from espec_gen eg
    left join cdre_onboarding co
      on co.dre_date = eg.dt
),
contract_costs as (
    select
      fc.dt,
      fc.property_id,
      fc.dt as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by fc.dt))::double precision as vl_bo_onboarding
    from filtered_contracts fc
    left join cdre_onboarding co
      on co.dre_date = fc.dt
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_bo_onboarding, cc.vl_bo_onboarding) as vl_bo_onboarding
  from tt_costs tt
  full outer join contract_costs cc
    on tt.dt_cash_flow = cc.dt_cash_flow
),
result as (
    select
      coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
      c.property_id,
      c.dt_cash_flow::date,
      c.vl_bo_onboarding,
      (c.vl_bo_onboarding is null)::int as flg_expected_bo_onboarding
    from full_costs c
    left join unit_economics.vw_base_property_costs vbpc
      on vbpc.property_id = c.property_id
        and c.dt >= vbpc.min_version_time
        and c.dt <= vbpc.max_version_time
),
m_avg_prev as (
    select distinct
        dt_cash_flow,
        avg(vl_bo_onboarding) over (partition by dt_cash_flow order by dt_cash_flow) as _avg1
    from result
    order by dt_cash_flow asc
),
last_value as (
    select
        dt_cash_flow,
        case
            when _avg1 is null
                and avg(_avg1) over (rows between 3 preceding and 1 preceding) is not null
                and lag(_avg1) over () is not null
                and lead(_avg1) over () is null
              then avg(_avg1) over (rows between 3 preceding and 1 preceding)
            else _avg1
        end as m_avg
    from m_avg_prev
),
last_value_gap_fill as (
    select
        dt_cash_flow,
        coalesce(m_avg, gap_fill(m_avg) over ()) as new_value
    from last_value
)
select
    r.sk_property,
    r.property_id,
    r.dt_cash_flow,
    r.flg_expected_bo_onboarding,
    lv.new_value as vl_bo_onboarding
from result r
join last_value_gap_fill lv
    on r.dt_cash_flow = lv.dt_cash_flow
;


create or replace view unit_economics.vw_mgmt_ops_bo_ongoing_costs as
with cdre_ongoing as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (ongoing)'
),
filtered_contracts_prev as (
    select distinct
      property_id,
      init_date as start_date,
      coalesce(termination_date, expected_end_date)::date as end_date
    from unit_economics.vw_base_contract_costs
    where init_date is not null
      and (termination_date is not null
            or expected_end_date is not null)
),
filtered_contract as (
    select distinct
      fc.property_id,
      fc.start_date,
      fc.end_date,
      date_trunc('month', dd."date")::date as dt_cash_flow
    from dim_date dd
    join filtered_contracts_prev fc
        on date_trunc('month', dd."date") between date_trunc('month', fc.start_date)  + interval '1 month'
                        and date_trunc('month', fc.end_date) + interval '1 month'
),
costs as (
    select distinct
      fc.property_id,
      fc.start_date,
      fc.end_date,
      fc.dt_cash_flow,
      co.dre_value,
      (count(fc.property_id) over (partition by fc.dt_cash_flow)),
      co.dre_value / (count(fc.property_id) over (partition by fc.dt_cash_flow))::double precision as vl_bo_ongoing,
      (dre_value is null)::int as flg_expected_bo_ongoing
    from filtered_contract fc
    left join cdre_ongoing co
      on co.dre_date = fc.dt_cash_flow
),
result as (
    select
      coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
      c.property_id,
      c.dt_cash_flow,
      c.vl_bo_ongoing,
      flg_expected_bo_ongoing
    from costs c
    left join unit_economics.vw_base_property_costs vbpc
      on vbpc.property_id = c.property_id
        and c.start_date >= vbpc.min_version_time
        and c.end_date <= vbpc.max_version_time
),
m_avg_prev as (
    select distinct
        dt_cash_flow,
        avg(vl_bo_ongoing) over (partition by dt_cash_flow order by dt_cash_flow) as _avg1
    from result
    order by dt_cash_flow asc
),
last_value as (
    select
        dt_cash_flow,
        case
            when _avg1 is null
                and avg(_avg1) over (rows between 3 preceding and 1 preceding) is not null
                and lag(_avg1) over () is not null
                and lead(_avg1) over () is null
              then avg(_avg1) over (rows between 3 preceding and 1 preceding)
            else _avg1
        end as m_avg
    from m_avg_prev
),
last_value_gap_fill as (
    select
        dt_cash_flow,
        coalesce(m_avg, gap_fill(m_avg) over ()) as new_value
    from last_value
)
select
    r.sk_property,
    r.property_id,
    r.dt_cash_flow,
    r.flg_expected_bo_ongoing,
    lv.new_value as vl_bo_ongoing
from result r
join last_value_gap_fill lv
    on r.dt_cash_flow = lv.dt_cash_flow
;


create or replace view unit_economics.vw_mgmt_ops_collection_costs as
with cdre_collection as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Collection'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Collection'
  group by property_id, dt
),
calculated_qt as (
  select
    property_id,
    dt,
    qt,
    avg(qt) over() as _avg
  from unit_economics.base_ticket_task
  where group_name = 'Collection'
    and property_id != -1
),
series as (
	select
		null::double precision as dre_value,
		generate_series((max(dre.dre_date) + interval '1 month')::date,
		    (max(dre.dre_date) + interval '60 month')::date, interval '1 month') as dre_date
	from cdre_collection dre
	group by dre_value

	union

	select dre_value, dre_date
	from cdre_collection
),
cdre_collection_fc as (
    select
        gap_fill(dre_value) over (order by dre_date) as dre_value,
        dre_date
    from series
),
rent_delay as (
  select
   contract_id,
   tenant_due_date,
   tenant_paid_date,
   date_part('day', cast(tenant_paid_date as timestamp) - cast(tenant_due_date as timestamp)) as rent_delayed_days
   from invoice
  where trim("from") = 'Inquilino'
   and trim(item) = 'Aluguel'
   and tenant_due_date is not null
   and tenant_paid_date is not null
),
filtered_contracts as (
    select distinct
      c.property_id as property_id,
      ccs.dre_date as dt,
      (date_part('year',  ccs.dre_date) - date_part('year', c.init_date)) * 12 +
              (date_part('month',  ccs.dre_date) - date_part('month', c.init_date)) as months_after_init
    from unit_economics.vw_base_contract_costs c
    join cdre_collection_fc ccs
      on ccs.dre_date between date_trunc('month', c.init_date) + interval '1 month'
                        and date_trunc('month', coalesce(c.termination_date, c.expected_end_date)) + interval '1 month'
    left join rent_delay rd
      on c.id = rd.contract_id
        and (rd.rent_delayed_days > 0
            or tenant_paid_date is null)
),
ratio as (
  select distinct
    fc.dt,
    qn.qt / count(fc.property_id) over (partition by fc.dt) as qt,
    fc.months_after_init
  from filtered_contracts fc
  left join qt_nulls qn
    on fc.dt = qn.dt
),
gen_contracts as (
	select distinct
		fc.property_id,
		fc.dt,
		r.qt as qt,
		avg(r.qt) over () as _avg,
		fc.months_after_init
	from filtered_contracts fc
    left join ratio r
  	    on fc.dt = r.dt
),
calculated as (
    select distinct
        property_id,
        dt,
        qt,
        avg(qt) over (partition by property_id) as _avg
    from calculated_qt
),
spec_gen_prev as (
  select
    coalesce(cc.property_id, gc.property_id) as property_id,
    coalesce(cc.dt, gc.dt) as dt,
    coalesce(cc.qt, 0) + coalesce(gc.qt, 0) as qt,
    coalesce(gc._avg, 0) + coalesce((gap_fill(cc._avg) over (partition by gc.property_id order by gc.dt)), 0) as _avg,
    gc.months_after_init
  from calculated cc
  full outer join gen_contracts gc
    on cc.property_id = gc.property_id
        and gc.dt = cc.dt
),
spec_gen as (
	select distinct
		property_id,
		dt,
		case
		    when qt = 0
		        then coalesce(_avg, 0)
		    else coalesce(qt, _avg)
		end as qt,
		case
		    when qt = 0 and _avg is not null
		        then 1
		    else 0
		end as flg_expected_collection
	from spec_gen_prev
),
tt_costs as (
    select distinct
      eg.property_id,
      eg.dt,
      co.dre_date as dt_cash_flow,
      co.dre_value * eg.qt / (sum(eg.qt) over (partition by co.dre_date))::double precision as vl_collection,
      flg_expected_collection
    from spec_gen eg
    join cdre_collection_fc co
      on co.dre_date = eg.dt + interval '1 month'
    where eg.qt > 0
),
contract_costs as (
    select
      fc.property_id,
      fc.dt,
      co.dre_date as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_collection
    from filtered_contracts fc
    join cdre_collection co
      on co.dre_date = date_trunc('month', fc.dt) + interval '1 month'
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_collection, cc.vl_collection) as vl_collection,
    coalesce(tt.flg_expected_collection, 0) as flg_expected_collection
  from tt_costs tt
  full outer join contract_costs cc
    on tt.property_id = cc.property_id and tt.dt = cc.dt
        and tt.dt_cash_flow = cc.dt_cash_flow
)
select
  vbpc.sk_property,
  fc.property_id,
  fc.dt_cash_flow::date,
  fc.vl_collection,
  flg_expected_collection
from full_costs fc
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = fc.property_id
    and fc.dt between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view unit_economics.vw_mgmt_ops_cs_post_sale_costs as
with cdre_cs_post_sale as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Customer Support (post-sale)'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Customer Support (post-sale)'
  group by property_id, dt
),
calculated_qt as (
  select
    property_id,
    dt,
    qt,
    avg(qt) over() as _avg
  from unit_economics.base_ticket_task
  where group_name = 'Customer Support (post-sale)'
    and property_id != -1
),
filtered_contracts_prev as (
    select distinct
      imovel_id as property_id,
      "dataInicio" as start_date,
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over w)::date as end_date
    from contract c
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
    window w as (partition by imovel_id)
),
series as (
	select
		null::double precision as dre_value,
		generate_series((max(dre.dre_date) + interval '1 month')::date,
		    (max(dre.dre_date) + interval '60 month')::date, interval '1 month') as dre_date
	from cdre_cs_post_sale dre

	union

	select dre_value, dre_date
	from cdre_cs_post_sale
),
cdre_cs_post_sale_fc as (
    select
        gap_fill(dre_value) over (order by dre_date) as dre_value,
        dre_date
    from series
),
filtered_contracts as (
  select distinct
    fcp.property_id,
    cps.dre_date - interval '1 month' as dt,
    (date_part('year',  cps.dre_date) - date_part('year', start_date)) * 12 +
              (date_part('month',  cps.dre_date) - date_part('month', start_date)) as months_after_init
  from filtered_contracts_prev fcp
  join cdre_cs_post_sale_fc cps
      on cps.dre_date between date_trunc('month', fcp.start_date) + interval '1 month'
                        and date_trunc('month', fcp.end_date) + interval '1 month'
  where cps.dre_date >= '2016-01-01'
),
ratio as (
  select distinct
    fc.dt,
    qn.qt / count(fc.property_id) over (partition by fc.dt) as qt,
    fc.months_after_init
  from filtered_contracts fc
  left join qt_nulls qn
    on fc.dt = qn.dt
),
gen_contracts as (
	select distinct
		fc.property_id,
		fc.dt,
		r.qt as qt,
		avg(r.qt) over () as _avg,
		fc.months_after_init
	from filtered_contracts fc
    left join ratio r
  	    on fc.dt = r.dt
),
calculated as (
    select distinct
        cqt.property_id,
        cqt.dt,
        cqt.qt,
        avg(qt) over (partition by property_id) as _avg
    from calculated_qt cqt
),
spec_gen_prev as (
  select
    coalesce(cc.property_id, gc.property_id) as property_id,
    coalesce(cc.dt, gc.dt) as dt,
    coalesce(cc.qt, 0) + coalesce(gc.qt, 0) as qt,
    coalesce(gc._avg, 0) + coalesce((gap_fill(cc._avg) over (partition by gc.property_id order by gc.dt)
                                        * (0.93 ^ gc.months_after_init)), 0) as _avg,
    gc.months_after_init
  from calculated cc
  full outer join gen_contracts gc
    on cc.property_id = gc.property_id
        and gc.dt = cc.dt
),
spec_gen as (
	select distinct
		property_id,
		dt,
		case
		    when qt = 0
		        then coalesce(_avg, 0)
		    else coalesce(qt, _avg)
		end as qt,
		case
		    when qt = 0 and _avg is not null
		        then 1
		    else 0
		end as flg_expected_cs_post_sale
	from spec_gen_prev
),
tt_costs as (
    select distinct
      eg.property_id,
      eg.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value * eg.qt / (sum(eg.qt) over (partition by cps.dre_date))::double precision as vl_cs_post_sale,
      flg_expected_cs_post_sale
    from spec_gen eg
    join cdre_cs_post_sale_fc cps
      on cps.dre_date = eg.dt + interval '1 month'
    where eg.qt > 0
),
contract_costs as (
    select
      fc.property_id,
      fc.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from filtered_contracts fc
    join cdre_cs_post_sale cps
      on cps.dre_date = fc.dt
    where fc.dt + interval '1 month' = cps.dre_date
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_cs_post_sale, cc.vl_cs_post_sale) as vl_cs_post_sale,
    coalesce(tt.flg_expected_cs_post_sale, 0) as flg_expected_cs_post_sale
  from tt_costs tt
  full outer join contract_costs cc
    on tt.property_id = cc.property_id and tt.dt = cc.dt
        and tt.dt_cash_flow = cc.dt_cash_flow
)
select
  coalesce(vbpc.sk_property, (fc.property_id || '001')::bigint) as sk_property,
  fc.property_id,
  fc.dt_cash_flow::date,
  fc.vl_cs_post_sale,
  fc.flg_expected_cs_post_sale
from full_costs fc
left join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = fc.property_id
    and fc.dt - interval '1 month' between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view unit_economics.vw_mgmt_ops_inspection_costs as
with cdre_inspections as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Inspections'
),
init_contract_costs as (
    select distinct
      property_id,
      id,
      date_trunc('month', signature_date)::date as dt
    from unit_economics.vw_base_contract_costs
    where signature_date is not null
),
end_contract_costs as (
   select distinct
      property_id,
      id,
      date_trunc('month', coalesce(termination_date, expected_end_date))::date as dt
    from unit_economics.vw_base_contract_costs
    where termination_date is not null
          or expected_end_date is not null
),
filtered_contracts as (
	select
		property_id,
    id,
		dt
	from
		init_contract_costs
	union
	select
		property_id,
    id,
		dt
	from
		end_contract_costs
),
contract_costs as (
	select
	  fc.property_id,
	  fc.dt,
	  coalesce(ci.dre_date, fc.dt) as dt_cash_flow,
	  ci.dre_value / (count(fc.property_id) over (partition by ci.dre_date))::double precision as vl_inspections,
	  (dre_value is null)::int as flg_expected_inspection
	from filtered_contracts fc
	left join cdre_inspections ci
	  on ci.dre_date = fc.dt + interval '1 month'
),
last_3_avg as (
	select
		t1.dt,
		t1.property_id,
		t1.dt_cash_flow,
		t1.vl_inspections,
		t1.flg_expected_inspection,
		avg(t2.vl_inspections) as m_avg
	from contract_costs t1
	join
		contract_costs t2
		on t2.dt_cash_flow >= t1.dt_cash_flow - interval '3 month' and t2.dt_cash_flow <= t1.dt_cash_flow
	group by t1.dt, t1.property_id, t1.dt_cash_flow, t1.vl_inspections, t1.flg_expected_inspection
),
coalesced_values as (
	select
		coalesce(vbpc.sk_property, (lavg.property_id || '001')::bigint) as sk_property,
		lavg.property_id,
		lavg.dt_cash_flow::date,
		case
			when dt_cash_flow >= '2017-01-01'
			then coalesce(vl_inspections,max(m_avg) filter (where flg_expected_inspection = 0) over ())
			else coalesce(vl_inspections, 0)
		end as vl_inspections,
		flg_expected_inspection
	from last_3_avg lavg
	left join unit_economics.vw_base_property_costs vbpc
	  on vbpc.property_id = lavg.property_id
	    and lavg.dt between vbpc.min_version_time and vbpc.max_version_time
)
select
	*
from
	coalesced_values
where
	vl_inspections != 0
;

create or replace view unit_economics.vw_mgmt_ops_costs as
select
	sk_property,
	property_id,
	date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
	sum(vl_bo_offboarding) as vl_bo_offboarding,
	sum(vl_bo_onboarding) as vl_bo_onboarding,
	sum(vl_bo_ongoing) as vl_bo_ongoing,
	sum(vl_collection) as vl_collection,
	sum(vl_cs_post_sale) as vl_cs_post_sale,
	sum(vl_inspections)  as vl_inspections,
	sum(flg_expected_bo_offboarding) as flg_expected_bo_offboarding,
  sum(flg_expected_bo_onboarding) as flg_expected_bo_onboarding,
  sum(flg_expected_bo_ongoing) as flg_expected_bo_ongoing,
  sum(flg_expected_collection) as flg_expected_collection,
  sum(flg_expected_cs_post_sale) as flg_expected_cs_post_sale,
  sum(flg_expected_inspection)  as flg_expected_inspection
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale,
		0 as vl_inspections,
		flg_expected as flg_expected_bo_offboarding,
    0 as flg_expected_bo_onboarding,
    0 as flg_expected_bo_ongoing,
    0 as flg_expected_collection,
    0 as flg_expected_cs_post_sale,
    0 as flg_expected_inspection
	from
		unit_economics.mgmt_ops_bo_offboarding_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale,
		0 as vl_inspections,
		0 as flg_expected_bo_offboarding,
    flg_expected_bo_onboarding as flg_expected_bo_onboarding,
    0 as flg_expected_bo_ongoing,
    0 as flg_expected_collection,
    0 as flg_expected_cs_post_sale,
    0 as flg_expected_inspection
	from
		unit_economics.mgmt_ops_bo_onboarding_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale,
		0 as vl_inspections,
		0 as flg_expected_bo_offboarding,
    0 as flg_expected_bo_onboarding,
    flg_expected_bo_ongoing as flg_expected_bo_ongoing,
    0 as flg_expected_collection,
    0 as flg_expected_cs_post_sale,
    0 as flg_expected_inspection
	from
		unit_economics.mgmt_ops_bo_ongoing_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		vl_collection,
		0 as vl_cs_post_sale,
		0 as vl_inspections,
		0 as flg_expected_bo_offboarding,
    0 as flg_expected_bo_onboarding,
    0 as flg_expected_bo_ongoing,
    flg_expected_collection as flg_expected_collection,
    0 as flg_expected_cs_post_sale,
    0 as flg_expected_inspection
	from
		unit_economics.mgmt_ops_collection_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		vl_cs_post_sale,
		0 as vl_inspections,
		0 as flg_expected_bo_offboarding,
    0 as flg_expected_bo_onboarding,
    0 as flg_expected_bo_ongoing,
    0 as flg_expected_collection,
    flg_expected_cs_post_sale as flg_expected_cs_post_sale,
    0 as flg_expected_inspection
	from
		unit_economics.mgmt_ops_cs_post_sale_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale,
		vl_inspections,
		0 as flg_expected_bo_offboarding,
    0 as flg_expected_bo_onboarding,
    0 as flg_expected_bo_ongoing,
    0 as flg_expected_collection,
    0 as flg_expected_cs_post_sale,
    flg_expected_inspection as flg_expected_inspection
	from
		unit_economics.mgmt_ops_inspection_costs
) tbl
group by sk_property, property_id, dt_cash_flow
;

create or replace view unit_economics.vw_mgmt_insurance_pis_cofins as
select
	sk_property,
	property_id,
	contract_id,
	-(vl_insurance_fee * 0.0925) as vl_st_pis_cofins,
	(date_trunc('month', dt_cash_flow) + interval '19 day')::date as dt_cash_flow,
	flg_expected
from
	unit_economics.vw_mgmt_insurance_fee
;

create or replace view unit_economics.vw_mgmt_insurance as
select
	coalesce(i_fee.sk_property, i_pis.sk_property) as sk_property,
	coalesce(i_fee.property_id, i_pis.property_id) as property_id,
	coalesce(i_fee.dt_cash_flow, i_pis.dt_cash_flow) as dt_cash_flow,
	coalesce(i_fee.vl_insurance_fee, 0) as vl_insurance_fee,
	coalesce(i_fee.vl_default_fee, 0) as vl_default_fee,
	coalesce(i_pis.vl_st_pis_cofins, 0) as vl_st_pis_cofins,
	coalesce(i_fee.flg_expected, 0) as flg_expected_insurance_fee,
	coalesce(i_pis.flg_expected, 0) as flg_expected_sales_tax_pis_cofins
from
	unit_economics.mgmt_insurance_fee i_fee
full outer join
	unit_economics.mgmt_insurance_pis_cofins i_pis
	on i_fee.sk_property = i_pis.sk_property
	and i_fee.dt_cash_flow = i_pis.dt_cash_flow
;

create or replace view unit_economics.vw_mgmt_costs as
select
  coalesce(ops.sk_property, ins.sk_property) as sk_property,
  coalesce(ops.property_id, ins.property_id) as property_id,
  coalesce(date_trunc('month', ops.dt_cash_flow)::date, date_trunc('month', ins.dt_cash_flow)::date) as dt_cash_flow,
  coalesce(ops.vl_bo_offboarding, 0) as vl_bo_offboarding,
  coalesce(ops.vl_bo_onboarding, 0) as vl_bo_onboarding,
  coalesce(ops.vl_bo_ongoing, 0) as vl_bo_ongoing,
  coalesce(ops.vl_collection, 0) as vl_collection,
  coalesce(ops.vl_cs_post_sale, 0) as vl_cs_post_sale,
  coalesce(ops.vl_inspections, 0) as vl_inspections,
  coalesce(ins.vl_default_fee, 0) as vl_default_fee,
  coalesce(ins.vl_insurance_fee, 0) as vl_insurance_fee,
  coalesce(ins.vl_st_pis_cofins, 0) as vl_st_pis_cofins,
  coalesce(ops.flg_expected_bo_offboarding, 0) as flg_expected_bo_offboarding,
  coalesce(ops.flg_expected_bo_onboarding, 0) as flg_expected_bo_onboarding,
  coalesce(ops.flg_expected_bo_ongoing, 0) as flg_expected_bo_ongoing,
  coalesce(ops.flg_expected_collection, 0) as flg_expected_collection,
  coalesce(ops.flg_expected_cs_post_sale, 0) as flg_expected_cs_post_sale,
  coalesce(ops.flg_expected_inspection, 0) as flg_expected_inspection,
  coalesce(ins.flg_expected_insurance_fee, 0) as flg_expected_insurance_fee,
  coalesce(ins.flg_expected_sales_tax_pis_cofins, 0) as flg_expected_sales_tax_pis_cofins
from
	unit_economics.mgmt_ops_costs ops
full outer join
	unit_economics.mgmt_insurance ins
	on ins.sk_property = ops.sk_property
     and ins.dt_cash_flow = ops.dt_cash_flow
;

create or replace view unit_economics.vw_liquidity_ab_agent_hours_costs as
with hour_costs as (
  select distinct
    cd.dre_date,
    sum(agent_commission.vl_agent_commission) over (partition by agent_commission.dt_cash_flow)
       +  cd.dre_value as hours
  from unit_economics.vw_net_revenue_agent_commission_costs agent_commission
  join unit_economics.vw_base_dre_costs cd
    on cd.dre_date = date_trunc('month', agent_commission.dt_cash_flow) - interval '2 month'
  where cd.dre_category = 'Agents Commission'
),
filtered_daily_status as  (
	select
		base.sk_property,
		id as property_id,
		"date" as dt_status,
		row_number()
			over (partition by isfh.id, base."version" order by isfh.id, isfh."date") as rn
	from
		imovel_status_full_history isfh
	left join
		unit_economics.vw_base_property_costs base
		on base.property_id = isfh.id
		where base.min_version_time <= isfh."date"
		and base.max_version_time > isfh."date"
	and status_history = 'publicado'
),
property_daily_status as  (
	select
		sk_property,
		property_id,
		dt_status
	from
		filtered_daily_status
	where
		rn <= 365
),
all_costs as (
    select
      pds.sk_property,
      pds.property_id,
      pds.dt_status,
      hc.dre_date as dt_cash_flow,
      hc.hours /
        date_part('days', hc.dre_date + interval '1 month' - interval '1 day') /
        (count(pds.property_id) over (partition by hc.dre_date))::double precision as vl_agent_hours
    from property_daily_status pds
    left join hour_costs hc
      on hc.dre_date = date_trunc('month', pds.dt_status) + interval '1 month'
)
select
  ac.sk_property,
  ac.property_id,
  ac.dt_cash_flow::date,
  case
    when sum(ac.vl_agent_hours) > 0
      then 0
    else sum(ac.vl_agent_hours)
  end as vl_agent_hours
from all_costs ac
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = ac.property_id
    and ac.dt_cash_flow between vbpc.min_version_time and vbpc.max_version_time
group by ac.sk_property, ac.property_id, ac.dt_cash_flow
;



create or replace view unit_economics.vw_liquidity_lockbox_costs as
with lockbox_dates as (
	select
		imovel_id as property_id,
		min(dt_added)::date as dt_cash_flow
	from
		property_visit_information pvi
	where
		pvi.informacoes_visita = 'CHAVE_CAIXA_QUINTOANDAR'
		and
		coalesce(date_part('days', dt_deleted - dt_added), 0) > 0
	group by imovel_id
)
select
	base.sk_property,
	base.property_id,
	lock.dt_cash_flow,
	56.00 as vl_lockbox
from
	unit_economics.vw_base_property_costs base
left join
	lockbox_dates lock
	on base.property_id = lock.property_id
	and lock.dt_cash_flow >= base.min_version_time and lock.dt_cash_flow < base.max_version_time
where lock.property_id is not null
;

create or replace view unit_economics.vw_liquidity_mkt_tenant_campaigns_costs as
-- Get Criteo Daily Costs (deduplicated)
with criteo_daily_costs as (
	select distinct
		"dateTime"::date as dt_cost,
		cost::decimal as cost
	from criteo_ads_campaigns
),
-- Get Google Daily Costs
google_daily_costs as (
	select
		"day"::date dt_cost,
		sum((cost::decimal/1000000)::decimal) as cost
	from
		google_ads_campaigns
	where
		-- exclude all supply campaigns
		(
			campaign like '%proprietarios%' or
			campaign like '%lp_quanto_cobrar%' or
			campaign like '%indicaai%'
		) is false
	group by
		"day"::date
),
-- Get Facebook Daily Costs
facebook_daily_costs as (
	select
	    "date"::date as dt_cost,
	    sum(spend::decimal) as cost
	from
	    facebook_ads_campaigns
	where
	    account_name <> 'Supply'
	group by
	    "date"::date
),
-- Get RTB Daily Costs
rtbhouse_daily_costs as (
	select
		"Date"::date as dt_cost,
		-sum(("Debit"::decimal(14,2))::decimal(14,2)) as cost
	from
		rtbhouse_ads_campaigns
	where
		"Debit" is not null
		and "Date" is not null
	group by
		"Date"::date
),
-- Join all marketing cost sources
union_costs as
(
	select
		dt_cost,
		0 as google,
		cost as rtb,
		0 as criteo,
		0 as facebook
	from
		rtbhouse_daily_costs
	union all
	select
		dt_cost,
		0 as google,
		0 as rtb,
		cost as criteo,
		0 as facebook
	from
		criteo_daily_costs
	union all
	select
		dt_cost,
		cost as google,
		0 as rtb,
		0 as criteo,
		0 as facebook
	from
		google_daily_costs
	union all
	select
		dt_cost,
		0 as google,
		0 as rtb,
		0 as criteo,
		cost as facebook
	from
		facebook_daily_costs
),
pre_classified as
(
	select
		dt_cost,
		sum(google) as google,
		sum(rtb) as rtbhouse,
		sum(facebook) as facebook,
		sum(criteo) as criteo,
		sum(google + rtb + facebook + criteo) as total
	from
		union_costs
	group by dt_cost
),
-- Add classified costs
daily_costs as (
select
	pc.dt_cost,
	pc.criteo,
	pc.google,
	pc.facebook,
	pc.rtbhouse,
	trim(replace("Total",',',''))::decimal(14,4)
	/ f_get_days_in_month("Date") as classifieds,
	(pc.total + (trim(replace("Total",',',''))::decimal(14,4)
	/ f_get_days_in_month("Date"))) as total
from
	files.classified_costs class
right join
	pre_classified pc
	on date_part('year',"Date") = date_part('year', pc.dt_cost)
	and date_part('month',"Date") = date_part('month', pc.dt_cost)
where
	"Date" is not null
),
-- For each property expose the published days
filtered_daily_status as  (
	select
		base.sk_property,
		id as property_id,
		"date" as dt_status,
		row_number()
			over (partition by isfh.id, base."version" order by isfh.id, isfh."date") as rn
	from
		imovel_status_full_history isfh
	left join
		unit_economics.vw_base_property_costs base
		on base.property_id = isfh.id
		where base.min_version_time <= isfh."date"
		and base.max_version_time > isfh."date"
	and status_history = 'publicado'
--	and id=892772473
),
-- For each property expose the published days
property_daily_status as  (
	select
		sk_property,
		property_id,
		dt_status
	from
		filtered_daily_status
	where
		rn <= 365
),
-- Divide costs for published day
daily_total as (
	select
		pds.sk_property as sk_property,
		pds.property_id as property_id,
		date_trunc('month', pds.dt_status + interval '2 month')::date as dt_cash_flow,
		coalesce(dc.total,0) as total,
		(coalesce(dc.criteo,0)/count(1) over ( partition by dt_status ))::decimal as criteo_cost,
		(coalesce(dc.google,0)/count(1) over ( partition by dt_status ))::decimal as google_cost,
		(coalesce(dc.facebook,0)/count(1) over ( partition by dt_status ))::decimal as facebook_cost,
		(coalesce(dc.rtbhouse,0)/count(1) over ( partition by dt_status ))::decimal as rtbhouse_cost,
		(coalesce(dc.classifieds,0)/count(1) over ( partition by dt_status ))::decimal as classifieds_cost,
		(coalesce(dc.total,0)/count(1) over ( partition by dt_status ))::decimal as total_cost
	from
		property_daily_status pds
	left join
		daily_costs dc
		on pds.dt_status = dt_cost
),
-- Get month total for each version with a proper cash flow date
monthly_total_versioned as (
	select
		daily.sk_property,
		daily.property_id,
		daily.dt_cash_flow,
		sum(daily.criteo_cost)::decimal(14,4) as criteo_cost,
		sum(daily.google_cost)::decimal(14,4) as google_cost,
		sum(daily.facebook_cost)::decimal(14,4) as facebook_cost,
		sum(daily.rtbhouse_cost)::decimal(14,4) as rtbhouse_cost,
		sum(daily.classifieds_cost)::decimal(14,4) as classifieds_cost,
		sum(daily.total_cost)::decimal(14,4) as vl_tenant_campaigns
	from
		daily_total daily
	group by
		daily.sk_property,
		daily.property_id,
		daily.dt_cash_flow
)
select
	*
from
	monthly_total_versioned
where
	vl_tenant_campaigns <> 0
;

create or replace view unit_economics.vw_liquidity_mkt_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	vl_tenant_campaigns
from
	unit_economics.liquidity_mkt_tenant_campaigns_costs
;

create or replace view unit_economics.vw_liquidity_ops_bo_pre_sale_costs as
with cdre_bo_pre_sale as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (pre-sale)'
),
filtered_contracts as (
    select distinct
      vbpc.sk_property,
      c.property_id,
      c.created_date::date as created_date
    from unit_economics.vw_base_property_costs vbpc
	left join unit_economics.vw_base_contract_costs c
	   on vbpc.property_id = c.property_id
    	and c.created_date between vbpc.min_version_time and vbpc.max_version_time
    where
		created_date is not null
	and -- check for max liquidity date
		c.created_date <=
		(case
			when min_version_time + interval '1 year' >= max_version_time
				then max_version_time
			when min_version_time + interval '1 year' >= now()
				then now()
			else
				min_version_time + interval '1 year'
		end)
),
costs as (
    select
      fc.sk_property,
      fc.property_id,
      fc.created_date,
      cps.dre_date as dt_cash_flow,
      cps.dre_value / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_bo_pre_sale
    from filtered_contracts fc
    join cdre_bo_pre_sale cps
      on cps.dre_date = date_trunc('month', fc.created_date) + interval '1 month'
)
select
  sk_property,
  c.property_id,
  c.dt_cash_flow,
  sum(c.vl_bo_pre_sale) as vl_bo_pre_sale
from costs c
group by c.property_id, c.dt_cash_flow, c.sk_property
;



create or replace view unit_economics.vw_liquidity_ops_cs_pre_sale_costs as
with cdre_cs_pre_sale as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Customer Support (pre-sale)'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Customer Support (pre-sale)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.base_ticket_task tt
  where tt.group_name = 'Customer Support (pre-sale)'
    and property_id != -1
),
filtered_properties_prev as (
    select distinct
        sk_property,
        property_id,
        publication_date::date,
        min_version_time::date,
		case
			when min_version_time + interval '1 year' >= max_version_time
				then max_version_time
			when min_version_time + interval '1 year' >= now()
				then now()
			else
				min_version_time + interval '1 year'
		end as max_liquidity_date
    from unit_economics.vw_base_property_costs
    where status = 'publicado'
),
filtered_properties as (
  select distinct
    fpp.sk_property,
    fpp.property_id,
    cps.dre_date - interval '1 month' as dt
  from filtered_properties_prev fpp
    join cdre_cs_pre_sale cps
      on cps.dre_date between date_trunc('month', fpp.min_version_time) + interval '1 month'
                        and date_trunc('month', fpp.max_liquidity_date) + interval '1 month'
),
ratio as (
  select distinct
    fp.dt,
    qn.qt / count(fp.property_id) over (partition by fp.dt) as qt
  from filtered_properties fp
  left join qt_nulls qn
    on fp.dt = qn.dt
),
gen_contracts as (
	select
	    fp.sk_property,
		fp.property_id,
		fp.dt,
		r.qt as qt_gen
	from
  	filtered_properties fp
  left join ratio r
  	on fp.dt = r.dt
),
espec_gen_prev as (
  select
    fp.sk_property,
    fp.property_id,
    cqt.dt as dt,
    cqt.qt as qt
  from
  	filtered_properties fp
  join calculated_qt cqt
    on cqt.property_id = fp.property_id
  union
  select
  	*
	from gen_contracts
),
espec_gen as (
	select
	    sk_property,
		property_id,
		dt,
		sum(qt) as qt
	from espec_gen_prev
	group by
		sk_property, property_id, dt
),
tt_costs as (
    select
      eg.sk_property,
      eg.property_id,
      eg.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value * eg.qt / (sum(eg.qt) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from espec_gen eg
    join cdre_cs_pre_sale cps
      on cps.dre_date = eg.dt + interval '1 month'
),
property_costs as (
    select
      fp.sk_property,
      fp.property_id,
      fp.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value / (count(fp.property_id) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from filtered_properties fp
    join cdre_cs_pre_sale cps
      on cps.dre_date = fp.dt
),
full_costs as (
  select distinct
    sk_property,
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_pre_sale
  from tt_costs
  where dt = dt_cash_flow

  union

  select distinct
    sk_property,
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_pre_sale
  from property_costs
  where dt = dt_cash_flow
)
select
  vbpc.sk_property,
  fc.property_id,
  fc.dt_cash_flow,
  fc.vl_cs_pre_sale
from full_costs fc
join unit_economics.vw_base_property_costs vbpc
  on vbpc.sk_property = fc.sk_property
;

create or replace view unit_economics.vw_liquidity_ops_field_ops_costs as
with cdre_field_ops as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category like 'Field Operation%'
),
filtered_visits as (
    select
      b.id as visit_id,
      vbpc.sk_property,
      b.imovel_id as property_id,
      b.data as dt
    from unit_economics.vw_base_property_costs vbpc
	left join booking b
	  on vbpc.property_id = b.imovel_id
	    and b.data between vbpc.min_version_time and vbpc.max_version_time
    where
		b.tipo = 'Visita'
	and -- visits before 2016-02 dont have fup
		(
		case
			when b.status = 'Realizado' then true
			when (b.status = 'Marcado' and data <= '2016-02-25'::date) then true
			else false
		end
		) = true
	and -- check for max liquidity date
		b.data <=
		(case
			when min_version_time + interval '1 year' >= max_version_time
				then max_version_time
			when min_version_time + interval '1 year' >= now()
				then now()
			else
				min_version_time + interval '1 year'
		end)
),
costs as (
    select
      fv.sk_property,
      fv.property_id,
      fv.dt,
      cfo.dre_date as dt_cash_flow,
      cfo.dre_value / (count(fv.property_id) over (partition by cfo.dre_date))::double precision as vl_field_ops
    from filtered_visits fv
    join cdre_field_ops cfo
      on cfo.dre_date = date_trunc('month', fv.dt) + interval '1 month'
)
select
  c.sk_property,
  c.property_id,
  c.dt_cash_flow,
  sum(c.vl_field_ops) as vl_field_ops
from costs c
group by c.sk_property, c.property_id, c.dt_cash_flow
;

create or replace view unit_economics.vw_liquidity_ops_costs as
select
	sk_property,
	property_id,
	date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
	sum(vl_bo_pre_sale) as vl_bo_pre_sale,
	sum(vl_cs_pre_sale) as vl_cs_pre_sale,
	sum(vl_field_ops) as vl_field_ops
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_bo_pre_sale,
		0 as vl_cs_pre_sale,
		0 as vl_field_ops
	from
		unit_economics.liquidity_ops_bo_pre_sale_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_pre_sale,
		vl_cs_pre_sale,
		0 as vl_field_ops
	from
		unit_economics.liquidity_ops_cs_pre_sale_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_pre_sale,
		0 as vl_cs_pre_sale,
		vl_field_ops
	from
		unit_economics.liquidity_ops_field_ops_costs
) tbl
group by sk_property, property_id, dt_cash_flow
;

create or replace view unit_economics.vw_liquidity_costs as
select
	sk_property,
	property_id,
	date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
	sum(vl_tenant_campaigns)::decimal(14,4) as vl_tenant_campaigns,
	sum(vl_bo_pre_sale) as vl_bo_pre_sale,
	sum(vl_cs_pre_sale) as vl_cs_pre_sale,
	sum(vl_field_ops) as vl_field_ops,
	sum(vl_agent_hours) as vl_agent_hours,
	sum(vl_lockbox) as vl_lockbox
from
	(
		select
			sk_property,
			property_id,
			dt_cash_flow,
			vl_tenant_campaigns,
			0 as vl_bo_pre_sale,
			0 as vl_cs_pre_sale,
			0 as vl_field_ops,
			0 as vl_agent_hours,
			0 as vl_lockbox
		from
			unit_economics.liquidity_mkt_costs
		union all
		select
			sk_property,
			property_id,
			dt_cash_flow,
			0 as vl_tenant_campaigns,
			0 as vl_bo_pre_sale,
			0 as vl_cs_pre_sale,
			0 as vl_field_ops,
			vl_agent_hours,
			0 as vl_lockbox
		from
			unit_economics.liquidity_ab_agent_hours_costs
		union all
		select
			sk_property,
			property_id,
			dt_cash_flow,
			0 as vl_tenant_campaigns,
			vl_bo_pre_sale,
			vl_cs_pre_sale,
			vl_field_ops,
			0 as vl_agent_hours,
			0 as vl_lockbox
		from
			unit_economics.liquidity_ops_costs
		union all
		select
			sk_property,
			property_id,
			dt_cash_flow,
			0 as vl_tenant_campaigns,
			0 as vl_bo_pre_sale,
			0 as vl_cs_pre_sale,
			0 as vl_field_ops,
			0 as vl_agent_hours,
			vl_lockbox
		from
			unit_economics.liquidity_lockbox_costs
	) tbl
group by sk_property, property_id, dt_cash_flow
;

create or replace view unit_economics.vw_fact_property_economics as
with unit_economics as (
    select
        sk_property,
        property_id,
        sk_cash_flow_date,
        dt_cash_flow,
        -sum(vl_owner_campaigns) as vl_owner_campaigns,
        -sum(vl_affiliate_campaigns) as vl_affiliate_campaigns,
        sum(vl_inside_sales) as vl_inside_sales,
        sum(vl_photos) as vl_photos,
        -sum(vl_affiliate_bonus) as vl_affiliate_bonus,
        -sum(vl_lockbox) as vl_lockbox,
        -sum(vl_tenant_campaigns) as vl_tenant_campaigns,
        sum(vl_cs_pre_sale) as vl_cs_pre_sale,
        sum(vl_field_ops) as vl_field_ops,
        sum(vl_bo_pre_sale) as vl_bo_pre_sale,
        sum(vl_agent_hours) as vl_agent_hours,
        -sum(vl_st_pis_cofins) as vl_st_pis_cofins,
        -sum(vl_st_iss) as vl_st_iss,
        -sum(vl_affiliate_commission) as vl_affiliate_commission,
        -sum(vl_agent_commission) as vl_agent_commission,
        sum(vl_delay_fine) as vl_delay_fine,
        0 as vl_termination_fine,
        sum(vl_brokerage_fee) as vl_brokerage_fee,
        sum(vl_management_fee) as vl_management_fee,
        sum(vl_cs_post_sale) as vl_cs_post_sale,
        sum(vl_collection) as vl_collection,
        sum(vl_bo_onboarding) as vl_bo_onboarding,
        sum(vl_bo_ongoing) as vl_bo_ongoing,
        sum(vl_bo_offboarding) as vl_bo_offboarding,
        sum(vl_inspections) as vl_inspections,
        -sum(vl_default_fee) as vl_default_fee,
        -sum(vl_insurance_fee) as vl_insurance_fee,
        sum(flg_expected_bo_offboarding) as flg_expected_bo_offboarding,
        sum(flg_expected_bo_onboarding) as flg_expected_bo_onboarding,
        sum(flg_expected_bo_ongoing) as flg_expected_bo_ongoing,
        sum(flg_expected_collection) as flg_expected_collection,
        sum(flg_expected_cs_post_sale) as flg_expected_cs_post_sale,
        sum(flg_expected_inspection) as flg_expected_inspection,
        sum(flg_expected_insurance_fee) as flg_expected_insurance_fee,
        sum(flg_expected_management_fee) as flg_expected_management_fee,
        sum(flg_expected_brokerage_fee) as flg_expected_brokerage_fee,
        sum(flg_expected_affiliate_commission) as flg_expected_affiliate_commission,
        sum(flg_expected_agent_commission) as flg_expected_agent_commission,
        sum(flg_expected_sales_tax_iss) as flg_expected_sales_tax_iss,
        sum(flg_expected_sales_tax_pis_cofins) as flg_expected_sales_tax_pis_cofins,
        sum(flg_expected_delay_fine) as flg_expected_delay_fine
    from
    (
        select
            sk_property,
            property_id,
            coalesce(replace(date_trunc('month',dt_cash_flow)::date::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
            0 as vl_owner_campaigns,
            0 as vl_affiliate_campaigns,
            0 as vl_inside_sales,
            0 as vl_photos,
            0 as vl_affiliate_bonus,
            vl_lockbox as vl_lockbox,
            vl_tenant_campaigns,
            vl_cs_pre_sale as vl_cs_pre_sale,
            vl_field_ops as vl_field_ops,
            vl_bo_pre_sale as vl_bo_pre_sale,
            vl_agent_hours as vl_agent_hours,
            0 as vl_st_pis_cofins,
            0 as vl_st_iss,
            0 as vl_affiliate_commission,
            0 as vl_agent_commission,
            0 as vl_delay_fine,
            0 as vl_termination_fine,
            0 as vl_brokerage_fee,
            0 as vl_management_fee,
            0 as vl_cs_post_sale,
            0 as vl_collection,
            0 as vl_bo_onboarding,
            0 as vl_bo_ongoing,
            0 as vl_bo_offboarding,
            0 as vl_inspections,
            0 as vl_default_fee,
            0 as vl_insurance_fee,
            0 as flg_expected_bo_offboarding,
            0 as flg_expected_bo_onboarding,
            0 as flg_expected_bo_ongoing,
            0 as flg_expected_collection,
            0 as flg_expected_cs_post_sale,
            0 as flg_expected_inspection,
            0 as flg_expected_insurance_fee,
            0 as flg_expected_management_fee,
            0 as flg_expected_brokerage_fee,
            0 as flg_expected_affiliate_commission,
            0 as flg_expected_agent_commission,
            0 as flg_expected_sales_tax_iss,
            0 as flg_expected_sales_tax_pis_cofins,
            0 as flg_expected_delay_fine
        from
            unit_economics.liquidity_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(date_trunc('month',dt_cash_flow)::date::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
            vl_owner_campaigns,
            vl_affiliate_campaigns,
            vl_inside_sales as vl_inside_sales,
            vl_photos as vl_photos,
            vl_affiliate_bonus,
            0 as vl_lockbox,
            0 as vl_tenant_campaigns,
            0 as vl_cs_pre_sale,
            0 as vl_field_ops,
            0 as vl_bo_pre_sale,
            0 as vl_agent_hours,
            0 as vl_st_pis_cofins,
            0 as vl_st_iss,
            0 as vl_affiliate_commission,
            0 as vl_agent_commission,
            0 as vl_delay_fine,
            0 as vl_termination_fine,
            0 as vl_brokerage_fee,
            0 as vl_management_fee,
            0 as vl_cs_post_sale,
            0 as vl_collection,
            0 as vl_bo_onboarding,
            0 as vl_bo_ongoing,
            0 as vl_bo_offboarding,
            0 as vl_inspections,
            0 as vl_default_fee,
            0 as vl_insurance_fee,
            0 as flg_expected_bo_offboarding,
            0 as flg_expected_bo_onboarding,
            0 as flg_expected_bo_ongoing,
            0 as flg_expected_collection,
            0 as flg_expected_cs_post_sale,
            0 as flg_expected_inspection,
            0 as flg_expected_insurance_fee,
            0 as flg_expected_management_fee,
            0 as flg_expected_brokerage_fee,
            0 as flg_expected_affiliate_commission,
            0 as flg_expected_agent_commission,
            0 as flg_expected_sales_tax_iss,
            0 as flg_expected_sales_tax_pis_cofins,
            0 as flg_expected_delay_fine
        from
            unit_economics.supply_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(date_trunc('month',dt_cash_flow)::date::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
            0 as vl_owner_campaigns,
            0 as vl_affiliate_campaigns,
            0 as vl_inside_sales,
            0 as vl_photos,
            0 as vl_affiliate_bonus,
            0 as vl_lockbox,
            0 as vl_tenant_campaigns,
            0 as vl_cs_pre_sale,
            0 as vl_field_ops,
            0 as vl_bo_pre_sale,
            0 as vl_agent_hours,
            vl_st_pis_cofins,
            0 as vl_st_iss,
            0 as vl_affiliate_commission,
            0 as vl_agent_commission,
            0 as vl_delay_fine,
            0 as vl_termination_fine,
            0 as vl_brokerage_fee,
            0 as vl_management_fee,
            vl_cs_post_sale as vl_cs_post_sale,
            vl_collection as vl_collection,
            vl_bo_onboarding as vl_bo_onboarding,
            vl_bo_ongoing as vl_bo_ongoing,
            vl_bo_offboarding as vl_bo_offboarding,
            vl_inspections as vl_inspections,
            vl_default_fee as vl_default_fee,
            vl_insurance_fee as vl_insurance_fee,
            flg_expected_bo_offboarding as flg_expected_bo_offboarding,
            flg_expected_bo_onboarding as flg_expected_bo_onboarding,
            flg_expected_bo_ongoing as flg_expected_bo_ongoing,
            flg_expected_collection as flg_expected_collection,
            flg_expected_cs_post_sale as flg_expected_cs_post_sale,
            flg_expected_inspection as flg_expected_inspection,
            flg_expected_insurance_fee as flg_expected_insurance_fee,
            0 as flg_expected_management_fee,
            0 as flg_expected_brokerage_fee,
            0 as flg_expected_affiliate_commission,
            0 as flg_expected_agent_commission,
            0 as flg_expected_sales_tax_iss,
            flg_expected_sales_tax_pis_cofins,
            0 as flg_expected_delay_fine
        from
            unit_economics.mgmt_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(date_trunc('month',dt_cash_flow)::date::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
            0 as vl_owner_campaigns,
            0 as vl_affiliate_campaigns,
            0 as vl_inside_sales,
            0 as vl_photos,
            0 as vl_affiliate_bonus,
            0 as vl_lockbox,
            0 as vl_tenant_campaigns,
            0 as vl_cs_pre_sale,
            0 as vl_field_ops,
            0 as vl_bo_pre_sale,
            0 as vl_agent_hours,
            vl_st_pis_cofins as vl_st_pis_cofins,
            vl_st_iss as vl_st_iss,
            vl_affiliate_commission as vl_affiliate_commission,
            vl_agent_commission as vl_agent_commission,
            vl_delay_fine as vl_delay_fine,
            0 as vl_termination_fine,
            vl_brokerage_fee as vl_brokerage_fee,
            vl_management_fee as vl_management_fee,
            0 as vl_cs_post_sale,
            0 as vl_collection,
            0 as vl_bo_onboarding,
            0 as vl_bo_ongoing,
            0 as vl_bo_offboarding,
            0 as vl_inspections,
            0 as vl_default_fee,
            0 as vl_insurance_fee,
            0 as flg_expected_bo_offboarding,
            0 as flg_expected_bo_onboarding,
            0 as flg_expected_bo_ongoing,
            0 as flg_expected_collection,
            0 as flg_expected_cs_post_sale,
            0 as flg_expected_inspection,
            0 as flg_expected_insurance_fee,
            flg_expected_management_fee as flg_expected_management_fee,
            flg_expected_brokerage_fee as flg_expected_brokerage_fee,
            flg_expected_affiliate_commission as flg_expected_affiliate_commission,
            flg_expected_agent_commission as flg_expected_agent_commission,
            flg_expected_sales_tax_iss as flg_expected_sales_tax_iss,
            flg_expected_sales_tax_pis_cofins as flg_expected_sales_tax_pis_cofins,
            flg_expected_delay_fine as flg_expected_delay_fine
        from
            unit_economics.net_revenue_costs
    ) tbl
    group by sk_property, property_id, sk_cash_flow_date, dt_cash_flow
),
contracts as (
	select
		id as sk_contract,
		property_id,
		signature_date as start_date,
		rent_value,
		case
			when coalesce(termination_date, expected_end_date)::date > now()::date
				then now()::date
			else coalesce(termination_date, expected_end_date)::date
		end as end_date
	from unit_economics.vw_base_contract_costs
	where signature_date is not null
	  and (termination_date is not null or expected_end_date is not null)
),
final_version as (
  select
    ue.sk_property,
    ue.property_id,
    coalesce(gap_fill(c.sk_contract) over (partition by ue.sk_property order by ue.sk_cash_flow_date asc), -1) as sk_contract,
    ue.sk_cash_flow_date,
    ue.dt_cash_flow,
    ue.vl_owner_campaigns,
    ue.vl_affiliate_campaigns,
    ue.vl_inside_sales,
    ue.vl_photos,
    ue.vl_affiliate_bonus,
    ue.vl_lockbox,
    ue.vl_tenant_campaigns,
    ue.vl_cs_pre_sale,
    ue.vl_field_ops,
    ue.vl_bo_pre_sale,
    ue.vl_agent_hours,
    ue.vl_st_pis_cofins,
   	case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_sales_tax_pis_cofins,
    ue.vl_st_iss,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_sales_tax_iss,
    ue.vl_affiliate_commission,
    case when ue.flg_expected_affiliate_commission >= 1 then 1 else 0 end as flg_expected_affiliate_commission,
    ue.vl_agent_commission,
    case when ue.flg_expected_affiliate_commission >= 1 then 1 else 0 end as flg_expected_agent_commission,
    ue.vl_delay_fine,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_delay_fine,
    ue.vl_termination_fine,
    ue.vl_brokerage_fee,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_brokerage_fee,
    ue.vl_management_fee,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_management_fee,
    ue.vl_cs_post_sale,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_cs_post_sale,
    ue.vl_collection,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_collection,
    ue.vl_bo_onboarding,
    case when ue.flg_expected_affiliate_commission >= 1 then 1 else 0 end as flg_expected_bo_onboarding,
    ue.vl_bo_ongoing,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_bo_ongoing,
    ue.vl_bo_offboarding,
    case when ue.flg_expected_affiliate_commission >= 1 then 1 else 0 end as flg_expected_bo_offboarding,
    ue.vl_inspections,
    case when ue.flg_expected_affiliate_commission >= 1 then 1 else 0 end as flg_expected_inspection,
    ue.vl_default_fee,
    ue.vl_insurance_fee,
    case when ue.dt_cash_flow >= current_date then 1 else 0 end as flg_expected_insurance_fee
  from unit_economics ue
  left join contracts c
    on ue.property_id = c.property_id
       and ue.dt_cash_flow between c.start_date and c.end_date
)
,
first_pubs as (
    select
        i.id as property_id,
        COALESCE(h.dt_first_publication, i.first_publication) AS first_publication
    from
        imovel i
    left join
        (
          select
              a.id,
            min(a.status_time) AS dt_first_publication
          from imovel_status_history a
          where a.published = 1
          group by a.id
        ) h
        ON h.id = i.id
),
before_loss_factor as (
    select
        fv.*,
		fv.dt_cash_flow as sk_date
    from final_version fv
    left join first_pubs dp
      on fv.property_id = dp.property_id
    where fv.sk_cash_flow_date != -1
),
fact_contract as (
	select
		blf.*,
		c."valorAluguel" as rent_value,
		(date_part('year', blf.sk_date) - date_part('year', c."dataAssinado"::date)) * 12 +
	              (date_part('month', blf.sk_date) - date_part('month', c."dataAssinado"::date)) as months_diff
	from before_loss_factor blf
	left join contract c
		on blf.sk_contract = c.id
),
fact_factor as (
    select
        fc.sk_property,
        fc.rent_value,
        fc.property_id,
        fc.sk_contract,
        fc.sk_cash_flow_date,
        fc.sk_date,
        fc.vl_owner_campaigns,
        fc.vl_affiliate_campaigns,
        fc.vl_inside_sales,
        fc.vl_photos,
        fc.vl_affiliate_bonus,
        fc.vl_lockbox,
        fc.vl_tenant_campaigns,
        fc.vl_cs_pre_sale,
        fc.vl_field_ops,
        fc.vl_bo_pre_sale,
        fc.vl_agent_hours,
        coalesce(fc.vl_st_pis_cofins * (1 - sum(cf.loss_factor)
                    filter (where fc.dt_cash_flow >= current_date)
                        over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_st_pis_cofins) as vl_st_pis_cofins,
        fc.flg_expected_sales_tax_pis_cofins,
        coalesce(fc.vl_st_iss * (1 - sum(cf.loss_factor)
                    filter (where fc.dt_cash_flow >= current_date)
                        over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_st_iss) as vl_st_iss,
        fc.flg_expected_sales_tax_iss,
        coalesce(fc.vl_bo_ongoing * (1 - sum(cf.loss_factor)
                filter (where fc.flg_expected_affiliate_commission = 1)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_affiliate_commission) as vl_affiliate_commission,
        fc.flg_expected_affiliate_commission,
        coalesce(fc.vl_agent_commission * (1 - sum(cf.loss_factor)
                filter (where fc.flg_expected_agent_commission = 1)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_agent_commission) as vl_agent_commission,
        fc.flg_expected_agent_commission,
        coalesce(fc.vl_delay_fine * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_delay_fine) as vl_delay_fine,
        fc.flg_expected_delay_fine,
        fc.vl_termination_fine,
        coalesce(fc.vl_brokerage_fee * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_brokerage_fee) as vl_brokerage_fee,
        fc.flg_expected_brokerage_fee,
        coalesce(fc.vl_management_fee * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_management_fee) as vl_management_fee,
        fc.flg_expected_management_fee,
        coalesce(fc.vl_cs_post_sale * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_cs_post_sale) as vl_cs_post_sale,
        fc.flg_expected_cs_post_sale,
        coalesce(fc.vl_collection * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_collection) as vl_collection,
        fc.flg_expected_collection,
        coalesce(fc.vl_bo_onboarding * (1 - sum(cf.loss_factor)
                filter (where fc.flg_expected_bo_onboarding = 1)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_bo_onboarding) as vl_bo_onboarding,
        fc.flg_expected_bo_onboarding,
        coalesce(fc.vl_bo_ongoing * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_bo_ongoing) as vl_bo_ongoing,
        fc.flg_expected_bo_ongoing,
        coalesce(fc.vl_bo_offboarding * (1 - sum(cf.loss_factor)
                filter (where fc.flg_expected_bo_offboarding = 1)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_bo_offboarding) as vl_bo_offboarding,
        fc.flg_expected_bo_offboarding,
        coalesce(fc.vl_inspections * (1 - sum(cf.loss_factor)
                filter (where fc.flg_expected_inspection = 1)
                    over (partition by fc.sk_property, fc.sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_inspections) as vl_inspections,
        fc.flg_expected_inspection,
        coalesce(fc.vl_default_fee * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_default_fee) as vl_default_fee,
        coalesce(fc.vl_insurance_fee * (1 - sum(cf.loss_factor)
                filter (where fc.dt_cash_flow >= current_date)
                    over (partition by fc.sk_property, sk_contract order by months_diff rows between unbounded preceding and current row)), fc.vl_insurance_fee) as vl_insurance_fee,
        fc.flg_expected_insurance_fee
    from fact_contract fc
    left join unit_economics.contract_factor cf
        on cf.months_after_signature = fc.months_diff
)
select
  coalesce(sk_property,-1) as sk_property,
	coalesce(property_id,-1) as property_id,
	coalesce(sk_contract,-1) as sk_contract,
	coalesce(sk_cash_flow_date,-1) as sk_cash_flow_date,
	vl_owner_campaigns,
	vl_affiliate_campaigns,
	vl_inside_sales,
	vl_photos,
	vl_affiliate_bonus,
	vl_lockbox,
	vl_tenant_campaigns,
	vl_cs_pre_sale,
	vl_field_ops,
	vl_bo_pre_sale,
	vl_agent_hours,
	vl_st_pis_cofins,
	flg_expected_sales_tax_pis_cofins,
	vl_st_iss,
	flg_expected_sales_tax_iss,
	vl_affiliate_commission,
	flg_expected_affiliate_commission,
	vl_agent_commission,
	flg_expected_agent_commission,
	vl_delay_fine,
	flg_expected_delay_fine,
	vl_termination_fine,
	vl_brokerage_fee,
	flg_expected_brokerage_fee,
	vl_management_fee,
	flg_expected_management_fee,
	vl_cs_post_sale,
	flg_expected_cs_post_sale,
	vl_collection,
	flg_expected_collection,
	vl_bo_onboarding,
	flg_expected_bo_onboarding,
	vl_bo_ongoing,
	flg_expected_bo_ongoing,
	vl_bo_offboarding,
	flg_expected_bo_offboarding,
	vl_inspections,
	flg_expected_inspection,
	vl_default_fee,
	vl_insurance_fee,
	flg_expected_insurance_fee
from fact_factor
;