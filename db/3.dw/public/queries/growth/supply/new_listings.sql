drop table if exists growth.new_listings;
create table growth.new_listings as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', dp.publication_date) as _year,
		date_part('month', dp.publication_date) as _month,
		date_part('week', dp.publication_date) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		(date_part('year', dp.publication_date)::varchar
			|| lpad(date_part('month', dp.publication_date)::varchar, 2, '0')
			|| lpad(date_part('week', dp.publication_date)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', dp.publication_date)::varchar
			|| lpad(date_part('month', dp.publication_date)::varchar, 2, '0'))::int  as concat_month,
		count(distinct dp.sk_property) as _count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
	group by date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date)
	order by date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date)
),
all_dates_region as (
  select
		date_part('year', dp.publication_date) as _year,
		date_part('month', dp.publication_date) as _month,
		date_part('week', dp.publication_date) as _week,
		r.long_region_name as region,
		r.city_name as city,
		(date_part('year', dp.publication_date)::varchar
			|| lpad(date_part('month', dp.publication_date)::varchar, 2, '0')
			|| lpad(date_part('week', dp.publication_date)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', dp.publication_date)::varchar
			|| lpad(date_part('month', dp.publication_date)::varchar, 2, '0'))::int  as concat_month,
		count(distinct dp.sk_property) as _count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
	left join dim_region r
		on dp.regiao_id = r.id
	group by r.long_region_name, r.city_name, date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date)
	order by r.long_region_name, r.city_name, date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),