drop table if exists growth.visitors;
create table growth.visitors as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', db.dt_scheduling) as _year,
		date_part('month', db.dt_scheduling) as _month,
		date_part('week', db.dt_scheduling) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		(date_part('year', db.dt_scheduling)::varchar
			|| lpad(date_part('month', db.dt_scheduling)::varchar, 2, '0')
			|| lpad(date_part('week', db.dt_scheduling)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', db.dt_scheduling)::varchar
			|| lpad(date_part('month', db.dt_scheduling)::varchar, 2, '0'))::int  as concat_month,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
	group by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling)
	order by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling)
),
all_dates_region as (
	select
		date_part('year', db.dt_scheduling) as _year,
		date_part('month', db.dt_scheduling) as _month,
		date_part('week', db.dt_scheduling) as _week,
		dr.long_region_name as region,
		dr.city_name as city,
		(date_part('year', db.dt_scheduling)::varchar
			|| lpad(date_part('month', db.dt_scheduling)::varchar, 2, '0')
			|| lpad(date_part('week', db.dt_scheduling)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', db.dt_scheduling)::varchar
			|| lpad(date_part('month', db.dt_scheduling)::varchar, 2, '0'))::int  as concat_month,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	group by dr.long_region_name, dr.city_name, date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling)
	order by dr.long_region_name, dr.city_name, date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),