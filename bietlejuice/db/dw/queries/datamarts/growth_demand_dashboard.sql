with funnel_counts as (
	SELECT
	   dbt.date as date,
	   co.city_group as city_group,
	   co.mkt_medium as mkt_medium,
	   co.mkt_channel as mkt_channel,
	   sum(co.total_daily_visits_booked) as visits_booked,
	   round(sum(co.cost)) as marketing_cost
	FROM
	marketing.fact_daily_demand_funnel_conversions co
	left join dim_date dbt on dbt.sk_date = co.sk_date
	WHERE dbt.date BETWEEN '2019-01-01' AND CURRENT_DATE - interval '1 day'
	group by 1, 2, 3, 4
),
dates as (
	select distinct 
		date,
		week_start,
		weekday_name
	from dim_date
	where date >= date('2019-01-01')
	and date < date('2020-01-01')
	order by 1
),
city_groups as (
	select distinct dr.regional, dr.city_group 
	from funnel_counts fc
	join dim_region dr on dr.city_group = fc.city_group
	where fc.city_group is not null
),
mkt_channels_mediums as (
	select distinct mkt_channel, mkt_medium 
	from funnel_counts
	where mkt_channel is not null
),
growth_dimensions as (
	select * 
	from dates, city_groups, mkt_channels_mediums
	order by 1, 2, 3, 4
)
select 
	gd.date,
	gd.week_start,
	gd.weekday_name,
	gd.regional,
	gd.city_group,
	gd.mkt_channel,
	gd.mkt_medium,
	coalesce(fc.visits_booked, 0) as visits_booked,
	coalesce(fc.marketing_cost, 0) as marketing_cost,
	gt.target_visits_booked,
	gt.target_marketing_cost
from growth_dimensions gd 
left join funnel_counts fc 
	on fc.date = gd.date
	and fc.city_group = gd.city_group
	and fc.mkt_channel = gd.mkt_channel
	and fc.mkt_medium = gd.mkt_medium
left join datalake_raw.gsheets_growth_targets gt
	on gt.dt = gd.date
	and gt.city_group = gd.city_group
	and gt.mkt_channel = gd.mkt_channel
	and gt.mkt_medium = gd.mkt_medium
order by 1, 4, 5, 6, 7
;
