drop table if exists growth.approved_by_insurer;
create table growth.approved_by_insurer as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', dp.dt_proposal_approved) as _year,
		date_part('month', dp.dt_proposal_approved) as _month,
		date_part('week', dp.dt_proposal_approved) as _week,
		date_part('day', dp.dt_proposal_approved) as _day,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved is not null
	group by date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved), date_part('week', dp.dt_proposal_approved), date_part('day', dp.dt_proposal_approved)
	order by date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved), date_part('week', dp.dt_proposal_approved), date_part('day', dp.dt_proposal_approved)
),
all_dates_region as (
	select
		date_part('year', dp.dt_proposal_approved) as _year,
		date_part('month', dp.dt_proposal_approved) as _month,
		date_part('week', dp.dt_proposal_approved) as _week,
		date_part('day', dp.dt_proposal_approved) as _day,
		dr.long_region_name as region,
		dr.city_name as city,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved is not null
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	group by dr.long_region_name, dr.city_name, date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved), date_part('week', dp.dt_proposal_approved), date_part('day', dp.dt_proposal_approved)
	order by dr.long_region_name, dr.city_name, date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved), date_part('week', dp.dt_proposal_approved), date_part('day', dp.dt_proposal_approved)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),
