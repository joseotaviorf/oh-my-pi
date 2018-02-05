--drop table if exists growth.qualifieds;
create table growth.qualifieds as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
	select
		date_part('year', f.dt_qualified) as _year,
		date_part('month', f.dt_qualified) as _month,
		date_part('week', f.dt_qualified) as _week,
		date_part('day', f.dt_qualified) as _day,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(f.dt_qualified) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
	group by date_part('year', f.dt_qualified), date_part('month', f.dt_qualified), date_part('week', f.dt_qualified), date_part('day', f.dt_qualified)
	order by date_part('year', f.dt_qualified), date_part('month', f.dt_qualified), date_part('week', f.dt_qualified), date_part('day', f.dt_qualified)
),
all_dates_region as (
  select
		date_part('year', f.dt_qualified) as _year,
		date_part('month', f.dt_qualified) as _month,
		date_part('week', f.dt_qualified) as _week,
		date_part('day', f.dt_qualified) as _day,
		r.long_region_name as region,
		r.city_name as city,
		count(f.dt_qualified) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
	left join dim_region r
		on cap.region_id = r.id
	group by r.long_region_name, r.city_name, date_part('year', f.dt_qualified), date_part('month', f.dt_qualified), date_part('week', f.dt_qualified), date_part('day', f.dt_qualified)
	order by r.long_region_name, r.city_name, date_part('year', f.dt_qualified), date_part('month', f.dt_qualified), date_part('week', f.dt_qualified), date_part('day', f.dt_qualified)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),
