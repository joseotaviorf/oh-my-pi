drop view vw_liquidity_mkt_tenant_campaigns_costs;
---
--- Returns vl_tenant_campaigns costs for each first version property
--- Cost: Tenant Daily Costs for Google Adwords, Facebook, Criteo and Classifieds
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
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
