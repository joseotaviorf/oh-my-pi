drop table if exists growth.offerers;
create table growth.offerers as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', dof.dt_first_sent) as _year,
		date_part('month', dof.dt_first_sent) as _month,
		date_part('week', dof.dt_first_sent) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		(date_part('year', dof.dt_first_sent)::varchar
			|| lpad(date_part('month', dof.dt_first_sent)::varchar, 2, '0')
			|| lpad(date_part('week', dof.dt_first_sent)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', dof.dt_first_sent)::varchar
			|| lpad(date_part('month', dof.dt_first_sent)::varchar, 2, '0'))::int  as concat_month,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.offer_submitted is true
	group by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent)
	order by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent)
),
all_dates_region as (
	select
		date_part('year', dof.dt_first_sent) as _year,
		date_part('month', dof.dt_first_sent) as _month,
		date_part('week', dof.dt_first_sent) as _week,
		dr.long_region_name as region,
		dr.city_name as city,
		(date_part('year', dof.dt_first_sent)::varchar
			|| lpad(date_part('month', dof.dt_first_sent)::varchar, 2, '0')
			|| lpad(date_part('week', dof.dt_first_sent)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', dof.dt_first_sent)::varchar
			|| lpad(date_part('month', dof.dt_first_sent)::varchar, 2, '0'))::int  as concat_month,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.offer_submitted is true
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	group by dr.long_region_name, dr.city_name, date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent)
	order by dr.long_region_name, dr.city_name, date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),