--drop table if exists growth.visits_booked;
create table growth.visits_booked as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', db.dt_created) as _year,
		date_part('month', db.dt_created) as _month,
		date_part('week', db.dt_created) as _week,
		date_part('day', db.dt_created) as _day,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.reason_category != 'Reschedule'
	group by date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
	order by date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
),
all_dates_region as (
	select
		date_part('year', db.dt_created) as _year,
		date_part('month', db.dt_created) as _month,
		date_part('week', db.dt_created) as _week,
		date_part('day', db.dt_created) as _day,
		dr.long_region_name as region,
		dr.city_name as city,
		count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.reason_category != 'Reschedule'
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	group by dr.long_region_name, dr.city_name, date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
	order by dr.long_region_name, dr.city_name, date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),
