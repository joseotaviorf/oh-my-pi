drop view if exists vw_base_property_costs cascade;
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
drop view if exists vw_net_revenue_revenues_management_fee cascade;
drop view if exists vw_net_revenue_agent_commission_costs;
drop view if exists vw_net_revenue_costs cascade;
drop view if exists vw_mgmt_ops_bo_offboarding_costs cascade;
drop view if exists vw_mgmt_ops_bo_onboarding_costs cascade;
drop view if exists vw_mgmt_ops_bo_ongoing_costs cascade;
drop view if exists vw_mgmt_ops_collections_costs cascade;
drop view if exists vw_mgmt_ops_cs_post_sale_costs cascade;
drop view if exists vw_mgmt_ops_costs cascade;
drop view if exists vw_mgmt_costs cascade;
drop view if exists vw_liquidity_mkt_tenant_campaigns_costs cascade;
drop view if exists vw_liquidity_ops_bo_pre_sale_costs cascade;
drop view if exists vw_liquidity_mkt_costs cascade;
drop view if exists vw_liquidity_ops_cs_pre_sale_costs cascade;
drop view if exists vw_liquidity_ops_field_ops_costs cascade;
drop view if exists vw_liquidity_ops_costs cascade;
drop view if exists vw_liquidity_costs cascade;
drop view if exists vw_fact_property_economics cascade;

create or replace view vw_base_property_costs as
select
  ((id || '00') || coalesce(version, 1))::bigint as sk_property,
  id as property_id,
  version,
  publication_date,
  coalesce(min_version_time, '1900-01-01')::date as min_version_time,
  coalesce(max_version_time, '2300-01-01')::date as max_version_time
from vw_property_listing
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
      vbpc.property_id,
      i.first_publication::date as listing_date
    from vw_base_property_costs vbpc
    join imovel i
      on i.id = vbpc.property_id
    where vbpc.version = 1
),
costs as (
    select
      fp.property_id,
      fp.listing_date,
      cis.dre_date as dt_cash_flow,
      cis."value" / (count(fp.property_id) over (partition by cis.dre_date))::double precision as vl_inside_sales
    from filtered_properties fp
    join cdre_inside_sales cis
      on cis.dre_date = date_trunc('month', fp.listing_date)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_inside_sales
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
where vbpc.version = 1
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
      id as property_id,
      min_version_time::date as listing_date
    from vw_property_listing
),
costs as (
    select
      fp.property_id,
      fp.listing_date,
      cp.dre_date + interval '1 month' as dt_cash_flow,
      cp."value" / (count(fp.property_id) over (partition by cp.dre_date))::double precision as vl_photos
    from filtered_properties fp
    join cdre_photos cp
      on cp.dre_date = date_trunc('month', fp.listing_date)
)
select
  vbpc.sk_property,
  c.property_id,
  make_date(extract(year from c.dt_cash_flow)::int, extract(month from c.dt_cash_flow)::int, 5) as dt_cash_flow,
  c.vl_photos
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.listing_date = vbpc.min_version_time::date
;


create or replace view vw_supply_ops_costs as
select
  coalesce(vsopc.sk_property, vsoisc.sk_property) as sk_property,
  coalesce(vsopc.property_id, vsoisc.sk_property) as property_id,
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
		date_part('month', "day"::date) as "month",
		date_part('year', "day"::date) as "year",
		sum((cost::DECIMAL(14,2)/1000000)::DECIMAL(14,2)) as cost
	from
		google_ads_campaigns
	where
		(
			campaign like '%proprietarios%' or
			campaign like '%lp_quanto_cobrar%'
		)
	group by
		date_part('month', "day"::date),
		date_part('year', "day"::date)
),
-- Get Facebook Owner Costs Per Year-Month
facebook_monthly_owner_costs as
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
        ) is false
    group by
        date_part('month', "date"::date),
        date_part('year', "date"::date)
),
-- Join all costs into one single table
owner_mkt_costs as
(
	select
		coalesce(g."month", f."month") as month,
		coalesce(g."year", f."year") as year,
		(coalesce(g.cost, 0) + coalesce(f.cost, 0)) as cost
	from
		google_monthly_owner_costs g
	full outer join
		facebook_monthly_owner_costs f
	on g."year" = f."year" and f."month" = g."month"
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
		))::decimal(14,4) as vl_owner_campaigns
	from
		vw_base_property_costs base
	left join
		owner_mkt_costs mkt
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
	vl_owner_campaigns <> 0
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

---
--- Returns vl_affiliate_commission costs for each first version property
--- Cost: Affiliate Commission on rented properties
--- Cash Flow Date: Date of Payment
---
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

---
--- Returns vl_affiliate_commission costs for each first version property
--- Cost: Affiliate Commission on rented properties
--- Cash Flow Date: Date of Payment
---
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
	imovel_id as property_id,
	id,
	(max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over (partition by imovel_id))::date as end_date
from
	contract
where
	tipo = 'FullService'
	and ("dataRescisao" is not null
	or "dataFimContratoPrevisto" is not null)
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
	landlord_paid_date as dt_cash_flow
from
	base_contract bc
left join
	invoice i
	on bc.contract_id = i.contract_id
where
	item = 'TaxaCorretagem'
and
	landlord_status = 'paid'
;

create or replace view vw_net_revenue_revenues_management_fee as
with filtered_contracts as (
select distinct
	imovel_id as property_id,
	id,
	(max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over (partition by imovel_id))::date as end_date
from
	contract
where
	tipo = 'FullService'
	and ("dataRescisao" is not null
	or "dataFimContratoPrevisto" is not null)
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
	landlord_paid_date as dt_cash_flow
from
	base_contract bc
left join
	invoice i
	on bc.contract_id = i.contract_id
where
	item = 'TaxaAdministracao'
and
	landlord_status = 'paid'
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
	vw_net_revenue_revenues_management_fee m_fee
	on b_fee.sk_property = m_fee.sk_property
	and b_fee.dt_cash_flow = m_fee.dt_cash_flow
;

create or replace view vw_net_revenue_agent_commission_costs as
with filtered_properties as (
  select
      comm.dt,
      coalesce(cont.property_id, c.imovel_id) as property_id,
      sum(comm.percentage * cont.rent) as vl_agent_commission
  from files.finance_agents_contract cont
  join files.finance_agents_commission comm
    on cont.agent_name = comm.agent_name
       and date_trunc('month', cont.signature_date) = comm.dt
  join contract c
    on c.id = cont.contract_id
  where cont.status = 'Ativo'
  group by comm.dt, cont.property_id, cont.contract_id, c.id, c.imovel_id
)
select
  vbpc.sk_property,
  fp.property_id,
  fp.dt as dt_cash_flow,
  fp.vl_agent_commission
from filtered_properties fp
join vw_base_property_costs vbpc
  on vbpc.property_id = fp.property_id
    and fp.dt between vbpc.min_version_time and vbpc.max_version_time
;

create or replace view vw_net_revenue_costs as
select
    coalesce(vnrcc.sk_property, vnrr.sk_property) as sk_property,
	coalesce(vnrcc.property_id, vnrr.property_id) as property_id,
	coalesce(vnrcc.dt_cash_flow, vnrr.dt_cash_flow) as dt_cash_flow,
    coalesce(vl_affiliate_commission, 0) as vl_affiliate_commission,
	coalesce(vl_management_fee, 0) as vl_management_fee,
	coalesce(vl_brokerage_fee, 0) as vl_brokerage_fee
from
    vw_net_revenue_commission_costs vnrcc
full outer join
    vw_net_revenue_revenues vnrr
    on vnrcc.sk_property = vnrr.sk_property
	and vnrcc.dt_cash_flow = vnrr.dt_cash_flow
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
      imovel_id as property_id,
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over (partition by imovel_id))::date as end_date
    from contract
    where tipo = 'FullService'
      and ("dataRescisao" is not null
           or "dataFimContratoPrevisto" is not null)
),
costs as (
    select
      fc.property_id,
      fc.end_date,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_offboarding
    from filtered_contracts fc
    join cdre_offboarding co
      on co.dre_date = date_trunc('month', fc.end_date)
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
      imovel_id as property_id,
      case
        when "dataAssinado"::date > "dataEntrada"::date
          then "dataEntrada"::date
        else "dataAssinado"::date
      end as "from",
      case
        when "dataAssinado"::date > "dataEntrada"::date
          then "dataAssinado"::date
        else "dataEntrada"::date
      end as "to"
    from contract
    where tipo = 'FullService'
      and "dataAssinado" is not null
      and "dataEntrada" is not null
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
      on co.dre_date between date_trunc('month', fc."from") and date_trunc('month', fc."to")
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
      imovel_id as property_id,
      "dataInicio" as start_date,
      coalesce("dataRescisao", "dataFimContratoPrevisto")::date as end_date
    from contract
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
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
      on co.dre_date between date_trunc('month', fc.start_date) and date_trunc('month', fc.end_date)
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

create or replace view vw_mgmt_ops_collections_costs as
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
cdre_collections as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Collection'
),
filtered_contracts as (
    select distinct
      c.imovel_id as property_id,
      rd.tenant_due_date as dt,
      rd.tenant_paid_date,
      rd.rent_delayed_days
    from contract c
    join rent_delay rd
      on c.id = rd.contract_id
    where c.tipo = 'FullService'
      and (rd.rent_delayed_days > 0 or tenant_paid_date is null)
),
costs as (
    select
      fc.property_id,
      fc.dt,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_collections
    from filtered_contracts fc
    join cdre_collections co
      on co.dre_date = date_trunc('month', fc.dt)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_collections
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
      imovel_id as property_id,
      "dataInicio"::date as start_date,
      coalesce("dataRescisao", "dataFimContratoPrevisto")::date as end_date
    from contract
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
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
      on cps.dre_date between date_trunc('month', fc.start_date) and date_trunc('month', fc.end_date)
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
  coalesce(offboarding.sk_property, onboarding.sk_property, ongoing.sk_property, collections.sk_property, post_sale.sk_property) as sk_property,
  coalesce(offboarding.property_id, onboarding.property_id, ongoing.property_id, collections.property_id, post_sale.property_id) as property_id,
  coalesce(offboarding.dt_cash_flow, onboarding.dt_cash_flow, ongoing.dt_cash_flow, collections.dt_cash_flow, post_sale.dt_cash_flow) as dt_cash_flow,
  coalesce(offboarding.vl_bo_offboarding, 0) as vl_bo_offboarding,
  coalesce(onboarding.vl_bo_onboarding, 0) as vl_bo_onboarding,
  coalesce(ongoing.vl_bo_ongoing, 0) as vl_bo_ongoing,
  coalesce(collections.vl_collections, 0) as vl_collections,
  coalesce(post_sale.vl_cs_post_sale, 0) as vl_cs_post_sale

from vw_mgmt_ops_bo_offboarding_costs offboarding

full outer join vw_mgmt_ops_bo_onboarding_costs onboarding
  on onboarding.sk_property = offboarding.sk_property
     and onboarding.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_bo_ongoing_costs ongoing
  on ongoing.sk_property = offboarding.sk_property
     and ongoing.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_collections_costs collections
  on collections.sk_property = offboarding.sk_property
     and collections.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_cs_post_sale_costs post_sale
  on post_sale.sk_property = offboarding.sk_property
     and post_sale.dt_cash_flow = offboarding.dt_cash_flow
;


create or replace view vw_mgmt_costs as
select
  ops.sk_property as sk_property,
  ops.property_id as property_id,
  ops.dt_cash_flow as dt_cash_flow,
  ops.vl_bo_offboarding,
  ops.vl_bo_onboarding,
  ops.vl_bo_ongoing,
  ops.vl_collections,
  ops.vl_cs_post_sale
from
	vw_mgmt_ops_costs ops
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
pre_classified as
(
	select
		coalesce(c.dt_cost, g.dt_cost, f.dt_cost) as dt_cost,
		coalesce(c.cost,0) as criteo,
		coalesce(g.cost,0) as google,
		coalesce(f.cost,0) as facebook,
		coalesce(r.cost,0) as rtbhouse,
		(
			coalesce(c.cost,0) +
			coalesce(g.cost,0) +
			coalesce(f.cost,0) +
			coalesce(r.cost,0)
		) as total
	from
		criteo_daily_costs c
	full outer join
		google_daily_costs g
		on c.dt_cost = g.dt_cost
	full outer join
		facebook_daily_costs f
		on coalesce(c.dt_cost, g.dt_cost) = f.dt_cost
	full outer join
		rtbhouse_daily_costs r
		on coalesce(c.dt_cost, g.dt_cost, f.dt_cost) = r.dt_cost
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
property_daily_status as  (
	select
		id as property_id,
		"date" as dt_status,
		status_history as status
	from
		imovel_status_full_history
	where status_history = 'publicado'
),
-- Divide costs for published day
daily_total as (
	select
		pds.property_id as property_id,
		pds.dt_status as dt_cost,
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
		base.sk_property,
		base.property_id,
		date_trunc('month', daily.dt_cost + interval '2 month')::date as dt_cash_flow,
		sum(daily.criteo_cost)::decimal(14,4) as criteo_cost,
		sum(daily.google_cost)::decimal(14,4) as google_cost,
		sum(daily.facebook_cost)::decimal(14,4) as facebook_cost,
		sum(daily.rtbhouse_cost)::decimal(14,4) as rtbhouse_cost,
		sum(daily.classifieds_cost)::decimal(14,4) as classifieds_cost,
		sum(daily.total_cost)::decimal(14,4) as vl_tenant_campaigns
	from
		vw_base_property_costs base
	left join
		daily_total daily
		on base.property_id = daily.property_id
		where base.min_version_time <= daily.dt_cost
		and base.max_version_time > daily.dt_cost
	group by
		base.sk_property,
		base.property_id,
		date_trunc('month', daily.dt_cost + interval '2 month')::date
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
      imovel_id as property_id,
      "criadoEm"::date as created_date,
      "dataAssinado"::date as signature_date
    from contract
    where tipo = 'FullService'
      and ("criadoEm" is not null
           or "dataAssinado" is not null)
),
costs as (
    select
      fc.property_id,
      fc.created_date,
      fc.signature_date,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_bo_pre_sale
    from filtered_contracts fc
    join cdre_bo_pre_sale cps
      on cps.dre_date = date_trunc('month', fc.created_date)
         or  cps.dre_date = date_trunc('month', fc.signature_date)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_pre_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and (c.created_date between vbpc.min_version_time and vbpc.max_version_time
         or c.signature_date between vbpc.min_version_time and vbpc.max_version_time)
;



create or replace view vw_liquidity_ops_cs_pre_sale_costs as
with cdre_cs_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (pre-sale)'
),

-- USE VW_BASE_PROPERTY_COSTS
filtered_properties as (
    select distinct
      id as property_id,
      min_version_time::date,
      max_version_time::date
    from vw_property_listing
    where last_status_version = 'publicado'
),
costs as (
    select
      fp.property_id,
      fp.min_version_time,
      fp.max_version_time,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fp.property_id) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from filtered_properties fp
    join cdre_cs_pre_sale cps
      on cps.dre_date between date_trunc('month', fp.min_version_time) and date_trunc('month', fp.max_version_time)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_pre_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.min_version_time = vbpc.min_version_time
    and c.max_version_time = vbpc.max_version_time
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
      id as visit_id,
      imovel_id as property_id,
      data as dt
    from booking
    where tipo = 'Visita'
        and status = 'Realizado'
),
costs as (
    select
      fv.property_id,
      fv.dt,
      cfo.dre_date as dt_cash_flow,
      cfo."value" / (count(fv.property_id) over (partition by cfo.dre_date))::double precision as vl_field_ops
    from filtered_visits fv
    join cdre_field_ops cfo
      on cfo.dre_date = date_trunc('month', fv.dt)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  sum(c.vl_field_ops) as vl_field_ops
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.dt between vbpc.min_version_time and vbpc.max_version_time
group by vbpc.sk_property, c.property_id, c.dt_cash_flow
;


create or replace view vw_liquidity_ops_costs as
select
  coalesce(bo_pre_sale.sk_property, pre_sale.sk_property, field_ops.sk_property) as sk_property,
  coalesce(bo_pre_sale.property_id, pre_sale.property_id, field_ops.property_id) as property_id,
  coalesce(bo_pre_sale.dt_cash_flow, pre_sale.dt_cash_flow, field_ops.dt_cash_flow) as dt_cash_flow,
  coalesce(bo_pre_sale.vl_bo_pre_sale, 0) as vl_bo_pre_sale,
  coalesce(pre_sale.vl_cs_pre_sale, 0) as vl_cs_pre_sale,
  coalesce(field_ops.vl_field_ops, 0) as vl_field_ops

from vw_liquidity_ops_bo_pre_sale_costs bo_pre_sale

full outer join vw_liquidity_ops_cs_pre_sale_costs pre_sale
  on pre_sale.sk_property = bo_pre_sale.sk_property
     and pre_sale.dt_cash_flow = bo_pre_sale.dt_cash_flow

full outer join vw_liquidity_ops_field_ops_costs field_ops
  on field_ops.sk_property = bo_pre_sale.sk_property
     and field_ops.dt_cash_flow = bo_pre_sale.dt_cash_flow
;

create or replace view vw_liquidity_costs as
select
  coalesce(mkt.sk_property, ops.sk_property) as sk_property,
  coalesce(mkt.property_id, ops.property_id) as property_id,
  coalesce(mkt.dt_cash_flow, ops.dt_cash_flow) as dt_cash_flow,
  coalesce(mkt.vl_tenant_campaigns, 0)::decimal(14,4) as vl_tenant_campaigns,
  coalesce(ops.vl_bo_pre_sale, 0) as vl_bo_pre_sale,
  coalesce(ops.vl_cs_pre_sale, 0) as vl_cs_pre_sale,
  coalesce(ops.vl_field_ops, 0) as vl_field_ops
from
	vw_liquidity_mkt_costs mkt
full outer join vw_liquidity_ops_costs ops
  on mkt.sk_property = ops.sk_property
     and mkt.dt_cash_flow = ops.dt_cash_flow
;

create or replace view vw_fact_property_economics as
select
	sk_property,
	property_id,
	sk_cash_flow_date,
	-sum(vl_owner_campaigns) as vl_owner_campaigns,
	-sum(vl_affiliate_campaigns) as vl_affiliate_campaigns,
	sum(vl_inside_sales) as vl_inside_sales,
	sum(vl_photos) as vl_photos,
	-sum(vl_affiliate_bonus) as vl_affiliate_bonus,
	(-1*cast(random()*10000 as int))::double precision as vl_lockbox,
	-sum(vl_tenant_campaigns) as vl_tenant_campaigns,
	sum(vl_cs_pre_sale) as vl_cs_pre_sale,
	sum(vl_field_ops) as vl_field_ops,
	sum(vl_bo_pre_sale) as vl_bo_pre_sale,
	(-1*cast(random()*10000 as int))::double precision as vl_agent_hours,
	(-1*cast(random()*10000 as int))::double precision as vl_pis_cofins,
	-sum(vl_affiliate_commission) as vl_affiliate_commission,
	(-1*cast(random()*10000 as int))::double precision as vl_agent_commission,
	(-1*cast(random()*10000 as int))::double precision as vl_delay_fine,
	(-1*cast(random()*10000 as int))::double precision as vl_termination_fine,
	sum(vl_brokerage_fee) as vl_brokerage_fee,
	sum(vl_management_fee) as vl_management_fee,
	sum(vl_cs_post_sale) as vl_cs_post_sale,
	sum(vl_collections) as vl_collections,
	sum(vl_bo_onboarding) as vl_bo_onboarding,
	sum(vl_bo_onboarding) as vl_bo_ongoing,
	sum(vl_bo_offboarding) as vl_bo_offboarding,
	(-1*cast(random()*10000 as int))::double precision as vl_insurance_fee
from
(
	select
		sk_property,
		property_id,
		coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
		0 as vl_owner_campaigns,
		0 as vl_affiliate_campaigns,
		0 as vl_inside_sales,
		0 as vl_photos,
		0 as vl_affiliate_bonus,
		0 as vl_lockbox,
		vl_tenant_campaigns,
		vl_cs_pre_sale as vl_cs_pre_sale,
		vl_field_ops as vl_field_ops,
		vl_bo_pre_sale as vl_bo_pre_sale,
		0 as vl_agent_hours,
		0 as vl_pis_cofins,
		0 as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collections,
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
		0 as vl_pis_cofins,
		0 as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collections,
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
		0 as vl_pis_cofins,
		0 as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		vl_cs_post_sale as vl_cs_post_sale,
		vl_collections as vl_collections,
		vl_bo_onboarding as vl_bo_onboarding,
		vl_bo_ongoing as vl_bo_ongoing,
		vl_bo_offboarding as vl_bo_offboarding,
		0 as vl_insurance_fee
	from
		vw_mgmt_costs
	union all
	select
		sk_property,
		property_id,
		coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
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
		0 as vl_pis_cofins,
		vl_affiliate_commission as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		vl_brokerage_fee as vl_brokerage_fee,
		vl_management_fee as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collections,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_bo_offboarding,
		0 as vl_insurance_fee
	from
		vw_net_revenue_costs
) tbl
group by sk_property, property_id, sk_cash_flow_date
;

