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
drop view if exists vw_net_revenue_costs cascade;
drop view if exists vw_mgmt_ops_bo_offboarding_costs cascade;
drop view if exists vw_mgmt_ops_bo_onboarding_costs cascade;
drop view if exists vw_mgmt_ops_bo_ongoing_costs cascade;
drop view if exists vw_mgmt_ops_collection_costs cascade;
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
    vbpc.version,
      vbpc.property_id,
      i.first_publication::date as listing_date
    from vw_base_property_costs vbpc
    join vw_dim_lead_conversion vdlc
      on vbpc.property_id = vdlc.id_imovel
    join imovel i
      on i.id = vbpc.property_id
    where vdlc."type" = 'InsideSales'
      and vbpc.version = 1
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
    and c.listing_date = vbpc.min_version_time::date
;


create or replace view vw_supply_ops_photos_costs as
with cdre_photos as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Photos'
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
    sk_property,
    property_id,
    dt_cash_flow,
    coalesce(vl_affiliate_commission, 0) as vl_affiliate_commission
from
    vw_net_revenue_affiliate_commission_costs
;

---
--- Returns vl_affiliate_commission costs for each first version property
--- Cost: Affiliate Commission on rented properties
--- Cash Flow Date: Date of Payment
---
create or replace view vw_net_revenue_costs as
select
    sk_property,
    property_id,
    dt_cash_flow,
    coalesce(vl_affiliate_commission, 0) as vl_affiliate_commission
from
    vw_net_revenue_commission_costs
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
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_offboarding
from costs c
join vw_base_property_costs vbpc
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
      (max("dataAssinado") over w)::date as "from",
      (max("dataEntrada") over w)::date as "to"
    from contract
    where tipo = 'FullService'
      and ("dataAssinado" is not null
           or "dataEntrada" is not null)
    window w as (partition by imovel_id)
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
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_onboarding
from costs c
join vw_base_property_costs vbpc
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
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over w)::date as end_date
    from contract
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
    window w as (partition by imovel_id)
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
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_ongoing
from costs c
join vw_base_property_costs vbpc
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
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_collection
    from filtered_contracts fc
    join cdre_collection co
      on co.dre_date = date_trunc('month', fc.dt)
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
      imovel_id as property_id,
      "dataInicio" as start_date,
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over w)::date as end_date
    from contract
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
    window w as (partition by imovel_id)
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
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_post_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.start_date >= vbpc.min_version_time
    and c.end_date <= vbpc.max_version_time
;


create or replace view vw_mgmt_ops_costs as
select
  coalesce(offboarding.sk_property, onboarding.sk_property, ongoing.sk_property, collection.sk_property, post_sale.sk_property) as sk_property,
  coalesce(offboarding.property_id, onboarding.property_id, ongoing.property_id, collection.property_id, post_sale.property_id) as property_id,
  coalesce(offboarding.dt_cash_flow, onboarding.dt_cash_flow, ongoing.dt_cash_flow, collection.dt_cash_flow, post_sale.dt_cash_flow) as dt_cash_flow,
  coalesce(offboarding.vl_bo_offboarding, 0) as vl_bo_offboarding,
  coalesce(onboarding.vl_bo_onboarding, 0) as vl_bo_onboarding,
  coalesce(ongoing.vl_bo_ongoing, 0) as vl_bo_ongoing,
  coalesce(collection.vl_collection, 0) as vl_collection,
  coalesce(post_sale.vl_cs_post_sale, 0) as vl_cs_post_sale

from vw_mgmt_ops_bo_offboarding_costs offboarding

full outer join vw_mgmt_ops_bo_onboarding_costs onboarding
  on onboarding.sk_property = offboarding.sk_property
     and onboarding.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_bo_ongoing_costs ongoing
  on ongoing.sk_property = offboarding.sk_property
     and ongoing.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_collection_costs collection
  on collection.sk_property = offboarding.sk_property
     and collection.dt_cash_flow = offboarding.dt_cash_flow

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
  ops.vl_collection,
  ops.vl_cs_post_sale
from
	vw_mgmt_ops_costs ops
;