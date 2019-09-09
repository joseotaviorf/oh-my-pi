with demand_targets_agg as (
	/* get demand targets company level by mkt_channel */
	select 
		city_group,
		"date"::date,
		"month",
		week_start,
		demand_channel,
		sum(visits_booked::float) as target_channel_visits_booked,
		null as target_channel_marketing_cost /** placeholder for target marketing cost **/
	from datalake_raw.gsheets_demand_targets 
	group by 1, 2, 3, 4, 5
),
demand_targets as (
	/* get demand targets growth level by mkt_channel & mkt_medium */
	select 
		dtco.city_group,
		dtco."date",
		dtco."month",
		dtco.week_start,
		dtco.demand_channel,
		dtco.target_channel_visits_booked,
		dtco.target_channel_marketing_cost,
		dtgr.mkt_channel,
		dtgr.mkt_medium,
		nullif(trim(dtgr.target_visits_booked), '')::float as share_medium_visits_booked,
		null as share_medium_marketing_cost, /*placeholder*/
		nullif(trim(dtgr.target_visits_booked), '')::float * dtco.target_channel_visits_booked as target_medium_visits_booked,
		null as target_medium_marketing_cost /*placeholder*/
	from demand_targets_agg dtco 
	left join datalake_raw.gsheets_growth_demand_targets dtgr
		on dtgr.dt = dtco."date"
		and dtgr.city_group = dtco.city_group
		and dtgr.mkt_channel = dtco.demand_channel
),
demand_realized as (
	select distinct
		dbt.date as date,
		dbt.week_start as week_start,
		dbt.weekday_name as weekday_name,
		trim(dbt.month_name) as month_name,
		co.city_group as city_group,
		co.mkt_channel as mkt_channel,
		co.mkt_medium as mkt_medium,
		sum(co.total_daily_visits_booked) over (partition by dbt.date, co.city_group, co.mkt_channel) ::decimal as realized_channel_visits_booked,
		sum(co.total_daily_visits_booked) over (partition by dbt.date, co.city_group, co.mkt_channel, co.mkt_medium) ::decimal as realized_medium_visits_booked,
		sum(co.cost) over (partition by dbt.date, co.city_group, co.mkt_channel) ::float as realized_channel_marketing_cost,
		sum(co.cost) over (partition by dbt.date, co.city_group, co.mkt_channel, co.mkt_medium) ::float as realized_medium_marketing_cost
	from marketing.fact_daily_demand_funnel_conversions co
	left join dim_date dbt on dbt.sk_date = co.sk_date
)
select 
	dt.city_group,
	dt."date",
	dt."month",
	dt.week_start,
	dt.mkt_channel,
	dt.mkt_medium,
	dt.target_channel_visits_booked,
	dt.target_channel_marketing_cost,
	dt.target_medium_visits_booked,
	dt.target_medium_marketing_cost,
	dr.realized_channel_visits_booked,
	dr.realized_medium_visits_booked,
	dr.realized_channel_marketing_cost,
	dr.realized_medium_marketing_cost
from demand_targets dt
left join demand_realized dr
	on dr."date" = dt."date"
	and dr.city_group = dt.city_group
	and dr.mkt_channel = dt.mkt_channel
	and dr.mkt_medium = dt.mkt_medium
where dt."date" >= date('2019-01-01')
order by 1, 2, 5, 6
;
