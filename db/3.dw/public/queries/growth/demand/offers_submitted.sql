--drop table if exists growth.offers_submitted;
create table growth.offers_submitted as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', dof.dt_first_sent) as _year,
		date_part('month', dof.dt_first_sent) as _month,
		date_part('week', dof.dt_first_sent) as _week,
		date_part('week', dof.dt_first_sent) as _day,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct dof.sk_offer) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_first_sent is not null
	group by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent), date_part('day', dof.dt_first_sent)
	order by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent), date_part('day', dof.dt_first_sent)
),
all_dates_region as (
	select
		date_part('year', dof.dt_first_sent) as _year,
		date_part('month', dof.dt_first_sent) as _month,
		date_part('week', dof.dt_first_sent) as _week,
		date_part('week', dof.dt_first_sent) as _day,
		dr.long_region_name as region,
		dr.city_name as city,
		count(distinct dof.sk_offer) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_first_sent is not null
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	group by dr.long_region_name, dr.city_name, date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent), date_part('day', dof.dt_first_sent)
	order by dr.long_region_name, dr.city_name, date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent), date_part('day', dof.dt_first_sent)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),
