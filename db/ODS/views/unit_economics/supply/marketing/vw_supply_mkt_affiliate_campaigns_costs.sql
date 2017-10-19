create or replace view vw_supply_mkt_affiliate_campaigns_costs as
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
        ) is false
    group by
        date_part('month', "date"::date),
        date_part('year', "date"::date)
),
supply_affiliate_costs as
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
)
select
sk_property,
imovel_id as property_id,
publication_date::date as sk_cash_flow_date,
(coalesce(mkt.cost, 0)/count(1) over (
	partition by
	date_part('year', publication_date),
	date_part('month', publication_date)
))::decimal(14,4) as vl_affiliate_campaigns
from
	vw_base_property_costs base
left join
	supply_affiliate_costs mkt
	on date_part('year', publication_date) = mkt.year
	and date_part('month', publication_date) = mkt.month