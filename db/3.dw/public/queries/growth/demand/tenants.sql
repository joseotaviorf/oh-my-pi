--drop table if exists growth.tenants;
create table growth.tenants as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', dc.dt_signature) as _year,
		date_part('month', dc.dt_signature) as _month,
		date_part('week', dc.dt_signature) as _week,
		date_part('day', dc.dt_signature) as _day,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct dc.id_contract) as _count
	from fact_liquidity_property_scheduling f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature is not null
	group by date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
	order by date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
),
all_dates_region as (
	select
		date_part('year', dc.dt_signature) as _year,
		date_part('month', dc.dt_signature) as _month,
		date_part('week', dc.dt_signature) as _week,
		date_part('day', dc.dt_signature) as _day,
		dr.long_region_name as region,
		dr.city_name as city,
		count(distinct dc.id_contract) as _count
	from fact_liquidity_property_scheduling f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature is not null
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	group by dr.long_region_name, dr.city_name, date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
	order by dr.long_region_name, dr.city_name, date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),
