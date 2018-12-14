drop view if exists unit_economics.vw_supply_mkt_affiliate_campaigns_costs;
---
--- Returns vl_affiliate_campaigns costs for each first version property
--- Cost: Affiliate Campaigns for Google Adwords, Facebook
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
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
            campaign_name like '%IA%' or
            campaign_name like '%indica%' or
            campaign_name like '%Indica%' or
            campaign_name like '%affiliate%' or
            campaign_name like '%doorman%'
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
		fact_house_listing_flows f
		on f.imovel_id = base.property_id
	left join
		lead l
		on f.lead_id = l.id
	left join
		usuario u
		on u.id = l.usuario_que_indicou_id::int
	where
		f.lead_id is not null
		and l.usuario_que_indicou_id is not null
		and l.tipo='Afiliado'
),
-- Divide all costs among versioned properties
divided_costs as (
	select
		sk_house_listing,
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