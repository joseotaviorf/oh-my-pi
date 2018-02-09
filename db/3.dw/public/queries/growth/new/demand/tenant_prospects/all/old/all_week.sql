drop table if exists growth.tenant_prospects_all_week;
create table growth.tenant_prospects_all_week as
with all_dates_all_week as (
	select
		date_part('year', db.dt_created) as _year,
		date_part('week', db.dt_created) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
	  count(distinct f.sk_user_visitor) as _count
  from fact_liquidity_property_scheduling f
  join dim_booking db
  	on f.sk_booking = db.sk_booking
  		and f.sk_booking != -1
    	and db.dt_created >= '2017-01-01'
	group by date_part('year', db.dt_created), date_part('week', db.dt_created)
	order by date_part('year', db.dt_created), date_part('week', db.dt_created)
),
all_dates as (
	select
    w._year,
    d._month,
    w._week,
    d._day,
    w.region,
    w.city,
    w._count as weekly_count
	from all_dates_all_week w
	join growth.tenant_prospects_all_day d
  	on d._year = w._year
      and d._week = w._week
),
partial_calc_aux as (
	select
		_year,
		_month,
		_week,
		_day,
		region,
		city,
		weekly_count
	from all_dates
),
partial_calc_lag_prev as (
	select distinct
		_year,
		_month,
		_week,
		region,
		city,
		weekly_count
	from partial_calc_aux
),
partial_calc_lag as (
	select
		_year,
		_month,
		_week,
		region,
		city,
		weekly_count,
		lag(weekly_count) over (order by _year, _month, _week) as prev_weekly_count
	from partial_calc_lag_prev
),
partial_calc_prev as (
	select
		pca._year,
		pca._month,
		pca._week,
		pca._day,
		pca.region,
		pca.city,
		pcl.prev_weekly_count,
		pca.weekly_count
	from partial_calc_aux pca
	join partial_calc_lag pcl
		on pca._year = pcl._year
			and pca._week = pcl._week
			and pca.region = pcl.region
			and pca.city = pcl.city
),
partial_calc as (
	select
		_year,
		_month,
		_week,
		_day,
		region,
		city,
		prev_weekly_count,
		weekly_count,
		round((weekly_count / prev_weekly_count::float) - 1.0, 4) as wow
	from partial_calc_prev
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
		0 as daily_count,
		prev_weekly_count,
		weekly_count,
		0 as monthly_count,
		0 as yearly_count,
		wow,
		0 as mtd_lag,
		0 as mtd,
		0 as ytd_lag,
		0 as ytd,
		0 as mom,
		0 as yoy
	from partial_calc
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
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy
from result
;
