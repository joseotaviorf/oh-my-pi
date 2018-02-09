drop table if exists growth.tenant_prospects_region_day;
create table growth.tenant_prospects_region_day as
with all_dates as (
	select
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
    date_part('week', db.dt_created) as _week,
    date_part('day', db.dt_created) as _day,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and f.sk_booking != -1
  		and db.dt_created is not null
  		and db.dt_created >= '2017-01-01'
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
  group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
  order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
),
partial_calc_aux as (
	select
		_year,
		_month,
		_week,
		_day,
		region,
		city,
		_count as daily_count
	from all_dates
),
result as (
	select
		(_year::varchar || lpad(_month::varchar, 2 , '0') || lpad(_day::varchar, 2, '0'))::integer as sk_date,
		case
			when _week = 1
				then to_date(_year::varchar || '0101', 'YYYYMMDD')
			else dateadd(week, _week::integer - 1, to_date(_year::varchar || '0101', 'YYYYMMDD'))::date
		end as sk_week_start_date,
		_year,
		_month,
		_week,
		_day,
		region,
		city,
		daily_count,
		0 as prev_weekly_count,
		0 as weekly_count,
		0 as monthly_count,
		0 as yearly_count,
		0 as wow,
		0 as mtd_lag,
		0 as mtd,
		0 as ytd_lag,
		0 as ytd,
		0 as mom,
		0 as yoy
	from partial_calc_aux
)
select
  sk_date,
	(date_part('year', sk_week_start_date)::varchar
		|| lpad(date_part('month', sk_week_start_date)::varchar, 2, '0')
		|| lpad(date_part('day', sk_week_start_date)::varchar, 2, '0'))::integer as sk_week_start_date,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count
from result
;