drop view if exists vw_base_property_costs cascade;
drop view if exists vw_base_contract_costs cascade;
drop view if exists vw_supply_ops_inside_sales_costs cascade;
drop view if exists vw_supply_ops_photos_costs cascade;
drop view if exists vw_supply_ops_costs cascade;
drop view if exists vw_supply_mkt_affiliate_campaigns_costs cascade;
drop view if exists vw_supply_mkt_owner_campaigns_costs cascade;
drop view if exists vw_supply_mkt_costs cascade;
drop view if exists vw_supply_affiliate_bonus_costs cascade;
drop view if exists vw_supply_costs cascade;
drop view if exists vw_net_revenue_affiliate_commission_costs cascade;
drop view if exists vw_net_revenue_commission_costs cascade;
drop view if exists vw_net_revenue_revenues cascade;
drop view if exists vw_net_revenue_revenues_brokerage_fee cascade;
drop view if exists vw_net_revenue_revenues_mgmt_fee cascade;
drop view if exists vw_net_revenue_agent_commission_costs cascade;
drop view if exists vw_net_revenue_revenues_brokerage_plus_mgmt_aux cascade;
drop view if exists vw_net_revenue_taxes_sales_tax_iss cascade;
drop view if exists vw_net_revenue_taxes_sales_tax_pis_cofins cascade;
drop view if exists vw_net_revenue_taxes_delay_fine cascade;
drop view if exists vw_net_revenue_taxes cascade;
drop view if exists vw_net_revenue_costs cascade;
drop view if exists vw_mgmt_ops_bo_offboarding_costs cascade;
drop view if exists vw_mgmt_ops_bo_onboarding_costs cascade;
drop view if exists vw_mgmt_ops_bo_ongoing_costs cascade;
drop view if exists vw_mgmt_ops_collection_costs cascade;
drop view if exists vw_mgmt_ops_cs_post_sale_costs cascade;
drop view if exists vw_mgmt_ops_costs cascade;
drop view if exists vw_mgmt_insurance_fee cascade;
drop view if exists vw_mgmt_costs cascade;
drop view if exists vw_liquidity_mkt_tenant_campaigns_costs cascade;
drop view if exists vw_liquidity_ops_bo_pre_sale_costs cascade;
drop view if exists vw_liquidity_mkt_costs cascade;
drop view if exists vw_liquidity_ops_cs_pre_sale_costs cascade;
drop view if exists vw_liquidity_ops_field_ops_costs cascade;
drop view if exists vw_liquidity_ops_costs cascade;
drop view if exists vw_liquidity_lockbox_costs cascade;
drop view if exists vw_liquidity_ab_agent_hours_costs cascade;
drop view if exists vw_liquidity_costs cascade;
drop view if exists vw_fact_property_economics cascade;

create or replace view vw_base_property_costs as
select
  ((id || '00') || coalesce(version, 1))::bigint as sk_property,
  id as property_id,
  version,
  min_version_time as publication_date,
  status,
  min_version_time,
  coalesce(max_version_time, '2300-01-01')::date as max_version_time
from vw_property_listing_ribs
;


create or replace view vw_base_contract_costs as
select
  id,
  imovel_id as property_id,
  status,
  "valorAluguel" as rent_value,
  "dataRescisao" as termination_date,
  "dataFimContratoPrevisto" as expected_end_date,
  "dataAssinado" as signature_date,
  "dataEntrada" as entrance_date,
  "dataInicio" as init_date,
  "criadoEm" as created_date
from contract
  where tipo = 'FullService'
    and status in ('Finalizado', 'Ativo')
;

create or replace view vw_supply_ops_inside_sales_costs as
with cdre_inside_sales as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Inside Sales'
),
filtered_properties as (
   select distinct
      sk_property,
      property_id,
      min_version_time::date as listing_date
    from vw_base_property_costs
    where version = 1
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      fp.listing_date,
      cis.dre_date as dt_cash_flow,
      cis."value" / (count(fp.property_id) over (partition by cis.dre_date))::double precision as vl_inside_sales
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

create or replace view vw_supply_ops_photos_costs as
with cdre_photos as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Listing Photos'
),
filtered_properties as (
   select distinct
      sk_property,
      property_id,
      min_version_time::date as listing_date
    from vw_base_property_costs
    where version = 1
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      fp.listing_date,
      cp.dre_date as dt_cash_flow,
      cp."value" / (count(fp.property_id) over (partition by cp.dre_date))::double precision as vl_photos
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


create or replace view vw_supply_ops_costs as
select
  coalesce(vsopc.sk_property, vsoisc.sk_property) as sk_property,
  coalesce(vsopc.property_id, vsoisc.property_id) as property_id,
  coalesce(vsopc.dt_cash_flow, vsoisc.dt_cash_flow) as dt_cash_flow,
  coalesce(vsopc.vl_photos, 0) as vl_photos,
  coalesce(vsoisc.vl_inside_sales, 0) as vl_inside_sales
from vw_supply_ops_photos_costs vsopc
full outer join vw_supply_ops_inside_sales_costs vsoisc
  on vsoisc.sk_property = vsopc.sk_property
     and vsoisc.dt_cash_flow = vsopc.dt_cash_flow
;


---
--- Returns vl_affiliate_campaigns costs for each first version property
--- Cost: Affiliate Campaigns for Google Adwords, Facebook
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view vw_supply_mkt_affiliate_campaigns_costs as
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
		base.*
	from
		vw_base_property_costs base
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
),
-- Divide all costs among versioned properties
divided_costs as (
	select
		sk_property,
		property_id,
		date_trunc('month', publication_date + interval '2 month')::date as dt_cash_flow,
		(coalesce(mkt.cost, 0)/count(1) over (
			partition by
			date_part('year', publication_date),
			date_part('month', publication_date)
		))::decimal(14,4) as vl_affiliate_campaigns
	from
		affiliate_filtered_base base
	left join
		affiliate_mkt_costs mkt
		on date_part('year', publication_date) = mkt.year
		and date_part('month', publication_date) = mkt.month
	-- filter by first version only, as is a supply cost
	where base.version = 1
)
-- Remove rows where costs equal zero
select
	*
from
	divided_costs
where
	vl_affiliate_campaigns <> 0
;




---
--- Returns vl_owner_campaigns costs for each versioned property
--- Cost: Owner Campaigns for Google Adwords, Facebook
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view vw_supply_mkt_owner_campaigns_costs as
-- Get Google Ads Owner Costs Per Year-Month
with google_monthly_owner_costs as (
	select
		"day"::date as dt_cost,
		sum((cost::DECIMAL(14,4)/1000000)::DECIMAL(14,2)) as cost
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
        sum(spend::DECIMAL(14,4)) as cost
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
		vw_base_property_costs base
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

---
--- Returns
---     vl_affiliate_campaigns
---     vl_owner_campaigns
---     sk_cash_flow_date
--- for each versioned property
---
create or replace view vw_supply_mkt_costs as
select
	coalesce(affiliate.sk_property, owner.sk_property) as sk_property,
	coalesce(affiliate.property_id, owner.property_id) as property_id,
	coalesce(affiliate.dt_cash_flow, owner.dt_cash_flow) as dt_cash_flow,
	coalesce(vl_affiliate_campaigns, 0) as vl_affiliate_campaigns,
	coalesce(vl_owner_campaigns, 0) as vl_owner_campaigns
from
	vw_supply_mkt_affiliate_campaigns_costs affiliate
full outer join
	vw_supply_mkt_owner_campaigns_costs owner
	on affiliate.sk_property = owner.sk_property
	and affiliate.dt_cash_flow = owner.dt_cash_flow
;


---
--- Returns vl_affiliate_bonus costs for each first version property
--- Cost: Affiliate Bonus on Listed properties
--- Cash Flow Date: Date of Payment
---
create or replace view vw_supply_affiliate_bonus_costs as
with affiliate_filtered_base as (
	select
		base.*
	from
		vw_base_property_costs base
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

---
--- Returns all supply costs
--- Cost: Aggregated Supply Costs
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view vw_supply_costs as
select
	coalesce(vsmc.sk_property, vsoc.sk_property, vsacc.sk_property) as sk_property,
	coalesce(vsmc.property_id, vsoc.property_id, vsacc.property_id) as property_id,
	coalesce(vsmc.dt_cash_flow, vsoc.dt_cash_flow, vsacc.dt_cash_flow) as dt_cash_flow,
	coalesce(vsmc.vl_affiliate_campaigns, 0) as vl_affiliate_campaigns,
	coalesce(vsmc.vl_owner_campaigns, 0) as vl_owner_campaigns,
	coalesce(vsoc.vl_photos, 0) as vl_photos,
	coalesce(vsoc.vl_inside_sales, 0) as vl_inside_sales,
	coalesce(vsacc.vl_affiliate_bonus, 0) as vl_affiliate_bonus
from
	vw_supply_mkt_costs vsmc
full outer join vw_supply_ops_costs vsoc
  	on vsmc.sk_property = vsoc.sk_property
	and vsmc.dt_cash_flow = vsoc.dt_cash_flow
full outer join vw_supply_affiliate_bonus_costs vsacc
	on vsacc.sk_property = coalesce(vsoc.sk_property, vsmc.sk_property)
	and vsacc.dt_cash_flow = coalesce(vsoc.dt_cash_flow, vsmc.dt_cash_flow)
;

create or replace view vw_net_revenue_affiliate_commission_costs as
with affiliate_filtered_base as (
	select
		base.*
	from
		vw_base_property_costs base
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
	valor as vl_affiliate_commission
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

create or replace view vw_net_revenue_agent_commission_costs as
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
  left join vw_base_contract_costs c
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
-- Agents Commission spreadsheet doesn't contain contracts before Feb-2016
all_contracts as (
  select
    c.property_id,
    -- '0.5' is the commission average of Jan-2016
    c.rent_value * 0.5 as vl_agent_commission,
    date_trunc('month', signature_date) as dt
  from vw_base_contract_costs c
  where date_trunc('month', signature_date) = '2016-01-01'

  union

  select
    property_id,
    vl_agent_commission,
    dt
  from filtered_properties
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
  ud.vl_agent_commission
from updated_dates ud
join vw_base_property_costs vbpc
  on vbpc.property_id = ud.property_id
    and ud.dt between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view vw_net_revenue_commission_costs as
select
    coalesce(affiliate.sk_property, agent.sk_property) as sk_property,
    coalesce(affiliate.property_id, agent.property_id) as property_id,
    coalesce(affiliate.dt_cash_flow, agent.dt_cash_flow) as dt_cash_flow,
    coalesce(affiliate.vl_affiliate_commission, 0) as vl_affiliate_commission,
    coalesce(agent.vl_agent_commission, 0) as vl_agent_commission
from
    vw_net_revenue_affiliate_commission_costs affiliate
full outer join vw_net_revenue_agent_commission_costs agent
  on affiliate.sk_property = agent.sk_property
     and affiliate.dt_cash_flow = agent.dt_cash_flow
;

create or replace view vw_net_revenue_revenues_brokerage_fee as
with filtered_contracts as (
select distinct
	property_id,
	id,
	coalesce(termination_date, expected_end_date)::date as end_date
from
	vw_base_contract_costs
where termination_date is not null
  or expected_end_date is not null
),
base_contract as (
	select
		base.*,
		c.id as contract_id
	from
		vw_base_property_costs base
	left join
		filtered_contracts c
		on base.property_id = c.property_id
		and c.end_date between base.min_version_time and base.max_version_time
)
select
	sk_property,
	property_id,
	amount::decimal(14,4) as vl_brokerage_fee,
	greatest(
		landlord_due_date,
		due_date,
		landlord_paid_date,
		(concat(
			substring(year_month from 1 for 4),'-',
			substring(year_month from 5 for 6)::int,'-',
			'15'))::date + interval '1 month'
	)::date as dt_cash_flow
from
	base_contract bc
left join
	invoice i
	on bc.contract_id = i.contract_id
where
	item = 'TaxaCorretagem'
and
	landlord_status = 'paid'
and
	"from" = 'Proprietario'
and
	"to" = 'Contrato'
;

create or replace view vw_net_revenue_revenues_mgmt_fee as
with filtered_contracts as (
select distinct
	property_id,
	id,
	coalesce(termination_date, expected_end_date)::date as end_date
from
	vw_base_contract_costs
where termination_date is not null
	or expected_end_date is not null
),
base_contract as (
	select
		base.*,
		c.id as contract_id
	from
		vw_base_property_costs base
	left join
		filtered_contracts c
		on base.property_id = c.property_id
		and c.end_date between base.min_version_time and base.max_version_time
)
select
	sk_property,
	property_id,
	amount::decimal(14,4) as vl_management_fee,
	greatest(landlord_due_date, due_date, landlord_paid_date) as dt_cash_flow
from
	base_contract bc
left join
	invoice i
	on bc.contract_id = i.contract_id
where
	item = 'TaxaAdministracao'
and
	landlord_status = 'paid'
and
	"from" = 'Proprietario'
and
	"to" = 'Contrato'
;


create or replace view vw_net_revenue_revenues as
select
	coalesce(b_fee.sk_property, m_fee.sk_property) as sk_property,
	coalesce(b_fee.property_id, m_fee.property_id) as property_id,
	coalesce(b_fee.dt_cash_flow, m_fee.dt_cash_flow) as dt_cash_flow,
	coalesce(vl_management_fee, 0) as vl_management_fee,
	coalesce(vl_brokerage_fee, 0) as vl_brokerage_fee
from
	vw_net_revenue_revenues_brokerage_fee b_fee
full outer join
	vw_net_revenue_revenues_mgmt_fee m_fee
	on b_fee.sk_property = m_fee.sk_property
	and b_fee.dt_cash_flow = m_fee.dt_cash_flow
;


create or replace view vw_net_revenue_revenues_brokerage_plus_mgmt_aux as
select
    coalesce(br.sk_property, mg.sk_property) as sk_property,
    coalesce(br.property_id, mg.property_id) as property_id,
    coalesce(br.vl_brokerage_fee, 0) + coalesce(mg.vl_management_fee, 0) as brokerage_plus_mgmt,
    coalesce(br.dt_cash_flow, mg.dt_cash_flow) as dt_cash_flow
  from vw_net_revenue_revenues_brokerage_fee br
  full outer join vw_net_revenue_revenues_mgmt_fee mg
    on br.sk_property = mg.sk_property
       and br.dt_cash_flow = mg.dt_cash_flow
  where br.vl_brokerage_fee > 0
    or mg.vl_management_fee > 0
;


create or replace view vw_net_revenue_taxes_sales_tax_iss as
with iss as (
  select
    sk_property,
    property_id,
    0.05 * brokerage_plus_mgmt as vl_st_iss,
    dt_cash_flow + interval '1 month' as dt_cash_flow
  from vw_net_revenue_revenues_brokerage_plus_mgmt_aux
)
select
  sk_property,
  property_id,
  vl_st_iss,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 25) as dt_cash_flow
from iss
;

create or replace view vw_net_revenue_taxes_sales_tax_pis_cofins as
with pis_cofins as (
    select
        sk_property,
        property_id,
        0.0925 * brokerage_plus_mgmt as vl_st_pis_cofins,
        dt_cash_flow + interval '1 month' as dt_cash_flow
    from vw_net_revenue_revenues_brokerage_plus_mgmt_aux
)
select
  sk_property,
  property_id,
  vl_st_pis_cofins,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 10) as dt_cash_flow
from pis_cofins
;

create or replace view vw_net_revenue_taxes_delay_fine as
with fines as (
  select
	inf.fine,
	inf.paid_date::date as dt,
	c.property_id as property_id
  from invoice_fines inf
  join vw_base_contract_costs c
    on inf.contract_id = c.id
)
select
  vbpc.sk_property,
  f.property_id,
  f.fine as vl_delay_fine,
  f.dt as dt_cash_flow
from fines f
join vw_base_property_costs vbpc
  on vbpc.property_id = f.property_id
    and f.dt between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view vw_net_revenue_taxes as
select
	sk_property,
	property_id,
	dt_cash_flow,
	sum(vl_st_iss) as vl_st_iss,
	sum(vl_st_pis_cofins) as vl_st_pis_cofins,
	sum(vl_delay_fine) as vl_delay_fine
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_st_iss,
		0 as vl_st_pis_cofins,
		0 as vl_delay_fine
	from
		vw_net_revenue_taxes_sales_tax_iss
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_st_iss,
		vl_st_pis_cofins,
		0 as vl_delay_fine
	from
		vw_net_revenue_taxes_sales_tax_pis_cofins
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_st_iss,
		0 as vl_st_pis_cofins,
		vl_delay_fine
	from
		vw_net_revenue_taxes_delay_fine
) tbl
group by sk_property, property_id, dt_cash_flow
;

create or replace view vw_net_revenue_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	sum(vl_affiliate_commission) as vl_affiliate_commission,
	sum(vl_management_fee) as vl_management_fee,
	sum(vl_brokerage_fee) as vl_brokerage_fee,
	sum(vl_agent_commission) as vl_agent_commission,
	sum(vl_st_iss) as vl_st_iss,
	sum(vl_st_pis_cofins) as vl_st_pis_cofins,
	sum(vl_delay_fine) as vl_delay_fine
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
		0 as vl_delay_fine
	from
		vw_net_revenue_commission_costs
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
		0 as vl_delay_fine
	from
		vw_net_revenue_revenues
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
		vl_delay_fine
	from
		vw_net_revenue_taxes
) tbl
group by sk_property, property_id, dt_cash_flow
;


create or replace view vw_mgmt_ops_bo_offboarding_costs as
with cdre_offboarding as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (offboarding)'
),
filtered_contracts as (
    select distinct
      property_id,
      coalesce(termination_date, expected_end_date)::date as end_date
    from vw_base_contract_costs
    where termination_date is not null
          or expected_end_date is not null
),
costs as (
    select
      fc.property_id,
      fc.end_date,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_offboarding
    from filtered_contracts fc
    join cdre_offboarding co
      on co.dre_date = date_trunc('month', fc.end_date) + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_offboarding
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.end_date between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view vw_mgmt_ops_bo_onboarding_costs as
with cdre_onboarding as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (onboarding)'
),
filtered_contracts as (
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
    from vw_base_contract_costs
    where signature_date is not null
      and init_date is not null
),
costs as (
    select
      fc.property_id,
      fc."from",
      fc."to",
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_onboarding
    from filtered_contracts fc
    join cdre_onboarding co
      on co.dre_date between date_trunc('month', fc."from")  + interval '1 month'
                        and date_trunc('month', fc."to") + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint )as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_onboarding
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c."from" >= vbpc.min_version_time
    and c."to" <= vbpc.max_version_time
;



create or replace view vw_mgmt_ops_bo_ongoing_costs as
with cdre_ongoing as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (ongoing)'
),
filtered_contracts as (
    select distinct
      property_id,
      init_date as start_date,
      coalesce(termination_date, expected_end_date)::date as end_date
    from vw_base_contract_costs
    where init_date is not null
      and (termination_date is not null
            or expected_end_date is not null)
),
costs as (
    select
      fc.property_id,
      fc.start_date,
      fc.end_date,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_ongoing
    from filtered_contracts fc
    join cdre_ongoing co
      on co.dre_date between date_trunc('month', fc.start_date)  + interval '1 month'
                        and date_trunc('month', fc.end_date) + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_ongoing
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.start_date >= vbpc.min_version_time
    and c.end_date <= vbpc.max_version_time
;


create or replace view vw_mgmt_ops_collection_costs as
with rent_delay as (
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
cdre_collection as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Collection'
),
filtered_contracts as (
    select distinct
      c.property_id as property_id,
      rd.tenant_due_date as dt,
      rd.tenant_paid_date,
      rd.rent_delayed_days
    from vw_base_contract_costs c
    join rent_delay rd
      on c.id = rd.contract_id
    where rd.rent_delayed_days > 0
        or tenant_paid_date is null
),
costs as (
    select
      fc.property_id,
      fc.dt,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_collection
    from filtered_contracts fc
    join cdre_collection co
      on co.dre_date = date_trunc('month', fc.dt) + interval '1 month'
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_collection
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.dt between vbpc.min_version_time and vbpc.max_version_time
;


create or replace view vw_mgmt_ops_cs_post_sale_costs as
with cdre_cs_post_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (post-sale)'
),
filtered_contracts as (
    select distinct
      property_id,
      init_date::date as start_date,
      coalesce(termination_date, expected_end_date)::date as end_date
    from vw_base_contract_costs
    where init_date is not null
      and (termination_date is not null
            or expected_end_date is not null)
),
costs as (
    select
      fc.property_id,
      fc.start_date,
      fc.end_date,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from filtered_contracts fc
    join cdre_cs_post_sale cps
      on cps.dre_date between date_trunc('month', fc.start_date) + interval '1 month'
                        and date_trunc('month', fc.end_date) + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_post_sale
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.start_date >= vbpc.min_version_time
    and c.end_date <= vbpc.max_version_time
;

create or replace view vw_mgmt_ops_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	sum(vl_bo_offboarding) as vl_bo_offboarding,
	sum(vl_bo_onboarding) as vl_bo_onboarding,
	sum(vl_bo_ongoing) as vl_bo_ongoing,
	sum(vl_collection) as vl_collection,
	sum(vl_cs_post_sale) as vl_cs_post_sale
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
		0 as vl_cs_post_sale
	from
		vw_mgmt_ops_bo_offboarding_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale
	from
		vw_mgmt_ops_bo_onboarding_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale
	from
		vw_mgmt_ops_bo_ongoing_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		vl_collection,
		0 as vl_cs_post_sale
	from
		vw_mgmt_ops_collection_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		vl_cs_post_sale
	from
		vw_mgmt_ops_cs_post_sale_costs
) tbl
group by sk_property, property_id, dt_cash_flow
;

create or replace view vw_mgmt_insurance_fee as
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
		vw_base_contract_costs c
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
insurance_dates as (
	select
		pd.contract_id,
		pd.property_id,
		dd."date" as dt_cash_flow,
		coalesce(case
			when dt_start < '2017-05-21'
			then rent * 0.0725
			else rent * 0.045
		end, 0) as cardiff_amount
	from
		pay_dates pd
	left join
		dim_date dd
		on pd.dt_first_pay <= dd."date"
		and pd.dt_last_pay >= dd."date"
		and date_part('day', pd.dt_first_pay) = date_part('day', dd."date")
		and dd."date" <= now()
	where dd."date" is not null
	and rent is not null
),
base_contract as (
	select
		base.*,
		c.contract_id
	from
		vw_base_property_costs base
	left join
		payed_contracts c
		on base.property_id = c.property_id
		and c.dt_end between base.min_version_time and base.max_version_time
)
select
	max(sk_property)::bigint as sk_property,
	bc.property_id,
	bc.contract_id,
	cardiff_amount::decimal(14,4) as vl_insurance_fee,
	dt_cash_flow as dt_cash_flow
from
	base_contract bc
left join
	insurance_dates i
	on bc.contract_id = i.contract_id
where coalesce(cardiff_amount, 0) > 0
group by bc.property_id, dt_cash_flow, vl_insurance_fee, bc.contract_id
;

create or replace view vw_mgmt_costs as
select
  coalesce(ops.sk_property, ins.sk_property) as sk_property,
  coalesce(ops.property_id, ins.property_id) as property_id,
  coalesce(ops.dt_cash_flow, ins.dt_cash_flow) as dt_cash_flow,
  coalesce(ops.vl_bo_offboarding, 0) as vl_bo_offboarding,
  coalesce(ops.vl_bo_onboarding, 0) as vl_bo_onboarding,
  coalesce(ops.vl_bo_ongoing, 0) as vl_bo_ongoing,
  coalesce(ops.vl_collection, 0) as vl_collection,
  coalesce(ops.vl_cs_post_sale, 0) as vl_cs_post_sale,
  coalesce(ins.vl_insurance_fee, 0) as vl_insurance_fee
from
	vw_mgmt_ops_costs ops
full outer join
	vw_mgmt_insurance_fee ins
	on ins.sk_property = ops.sk_property
     and ins.dt_cash_flow = ops.dt_cash_flow
;

create or replace view vw_liquidity_mkt_tenant_campaigns_costs as
-- Get Criteo Daily Costs (deduplicated)
with criteo_daily_costs as (
	select distinct
		"dateTime"::date as dt_cost,
		cost::DECIMAL as cost
	from criteo_ads_campaigns
),
-- Get Google Daily Costs
google_daily_costs as (
	select
		"day"::date dt_cost,
		sum((cost::DECIMAL/1000000)::DECIMAL) as cost
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
	    sum(spend::DECIMAL) as cost
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
		-sum(("Debit"::DECIMAL(14,2))::DECIMAL(14,2)) as cost
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
	trim(REPLACE("Total",',',''))::decimal(14,4)
	/ f_get_days_in_month("Date") as classifieds,
	(pc.total + (trim(REPLACE("Total",',',''))::decimal(14,4)
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
		vw_base_property_costs base
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

create or replace view vw_liquidity_mkt_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	vl_tenant_campaigns
from
	vw_liquidity_mkt_tenant_campaigns_costs
;

create or replace view vw_liquidity_ops_bo_pre_sale_costs as
with cdre_bo_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (pre-sale)'
),
filtered_contracts as (
    select distinct
      vbpc.sk_property,
      c.property_id,
      c.created_date::date as created_date
    from vw_base_property_costs vbpc
	left join vw_base_contract_costs c
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
      cps."value" / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_bo_pre_sale
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



create or replace view vw_liquidity_ops_cs_pre_sale_costs as
with cdre_cs_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (pre-sale)'
),
filtered_properties as (
    select distinct
      sk_property,
      property_id,
      publication_date::date,
      min_version_time::date,
      max_version_time::date
    from vw_base_property_costs
    where status = 'publicado'
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fp.property_id) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from filtered_properties fp
    join cdre_cs_pre_sale cps
      on cps.dre_date between date_trunc('month', fp.min_version_time) + interval '1 month'
         and date_trunc('month', fp.max_version_time) + interval '1 month'
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_pre_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.sk_property = c.sk_property
;



create or replace view vw_liquidity_ops_field_ops_costs as
with cdre_field_ops as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Field Operation'
),
filtered_visits as (
    select
      b.id as visit_id,
      vbpc.sk_property,
      b.imovel_id as property_id,
      b.data as dt
    from vw_base_property_costs vbpc
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
      cfo."value" / (count(fv.property_id) over (partition by cfo.dre_date))::double precision as vl_field_ops
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

create or replace view vw_liquidity_lockbox_costs as
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
	vw_base_property_costs base
left join
	lockbox_dates lock
	on base.property_id = lock.property_id
	and lock.dt_cash_flow >= base.min_version_time and lock.dt_cash_flow < base.max_version_time
where lock.property_id is not null
;

create or replace view vw_liquidity_ops_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
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
		vw_liquidity_ops_bo_pre_sale_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_pre_sale,
		vl_cs_pre_sale,
		0 as vl_field_ops
	from
		vw_liquidity_ops_cs_pre_sale_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_pre_sale,
		0 as vl_cs_pre_sale,
		vl_field_ops
	from
		vw_liquidity_ops_field_ops_costs
) tbl
group by sk_property, property_id, dt_cash_flow
;

create or replace view vw_liquidity_ab_agent_hours_costs as
with hour_costs as (
  select distinct
    cd."Month" as dre_date,
    sum(agent_commission.vl_agent_commission) over (partition by agent_commission.dt_cash_flow)
       +  cd."Value" as hours
  from vw_net_revenue_agent_commission_costs agent_commission
  join files.costs_dre cd
    on cd."Month" = date_trunc('month', agent_commission.dt_cash_flow) - interval '2 month'
  where cd."Category" = 'Agents Commission'
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
		vw_base_property_costs base
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
join vw_base_property_costs vbpc
  on vbpc.property_id = ac.property_id
    and ac.dt_cash_flow between vbpc.min_version_time and vbpc.max_version_time
group by ac.sk_property, ac.property_id, ac.dt_cash_flow
;

create or replace view vw_liquidity_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
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
			vw_liquidity_mkt_costs
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
			vw_liquidity_ab_agent_hours_costs
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
			vw_liquidity_ops_costs
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
			vw_liquidity_lockbox_costs
	) tbl
group by sk_property, property_id, dt_cash_flow
;


create or replace view vw_fact_property_economics as
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
        -sum(vl_insurance_fee) as vl_insurance_fee
    from
    (
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
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
            0 as vl_insurance_fee
        from
            vw_liquidity_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
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
            0 as vl_insurance_fee
        from
            vw_supply_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
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
            0 as vl_st_pis_cofins,
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
            vl_insurance_fee as vl_insurance_fee
        from
            vw_mgmt_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
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
            0 as vl_insurance_fee
        from
            vw_net_revenue_costs
    ) tbl
    group by sk_property, property_id, sk_cash_flow_date, dt_cash_flow
),
-- change to fact_liquidity when versioning is fixed
contracts as (
	select
		id as sk_contract,
		property_id,
		signature_date as start_date,
		case
			when coalesce(termination_date, expected_end_date)::date > now()::date
				then now()::date
			else coalesce(termination_date, expected_end_date)::date
		end as end_date
	from vw_base_contract_costs
	where signature_date is not null
	  and (termination_date is not null or expected_end_date is not null)
),
final_version as (
  select
    ue.sk_property,
    ue.property_id,
    coalesce(c.sk_contract, -1) as sk_contract,
    ue.sk_cash_flow_date,
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
    ue.vl_st_iss,
    ue.vl_affiliate_commission,
    ue.vl_agent_commission,
    ue.vl_delay_fine,
    ue.vl_termination_fine,
    ue.vl_brokerage_fee,
    ue.vl_management_fee,
    ue.vl_cs_post_sale,
    ue.vl_collection,
    ue.vl_bo_onboarding,
    ue.vl_bo_ongoing,
    ue.vl_bo_offboarding,
    ue.vl_insurance_fee
  from unit_economics ue
  left join contracts c
    on ue.property_id = c.property_id
       and ue.dt_cash_flow between c.start_date and c.end_date
)
select fv.*
from final_version fv
left join vw_dim_property_ribs dp
  on fv.sk_property = dp.sk_property
where fv.sk_cash_flow_date != -1
      and coalesce(replace(dp.first_publication::date::varchar, '-', '')::integer, -1) <= fv.sk_cash_flow_date
;