drop view vw_supply_mkt_owner_campaigns_costs;
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