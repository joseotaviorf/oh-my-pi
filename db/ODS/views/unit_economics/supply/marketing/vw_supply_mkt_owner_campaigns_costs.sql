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
		imovel_id as property_id,
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
)
-- Remove rows where costs equal zero
select
	*
from
	divided_costs
where
	vl_owner_campaigns <> 0