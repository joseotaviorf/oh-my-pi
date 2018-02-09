drop table if exists growth.tenant_prospects_region_year;
create table growth.tenant_prospects_region_year as
with all_dates_region_year as (
	select
		date_part('year', db.dt_created) as _year,
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
	group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created)
	order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created)
),
all_dates as (
	select distinct
    y._year,
    d._month,
    w._week,
    d._day,
    y.region,
    y.city,
    y._count as yearly_count
	from growth.tenant_prospects_region_day d
	join growth.tenant_prospects_region_week w
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_region_year y
  	on d.city = y.city
  		and d.region = y.region
  		and d._year = y._year
),
partial_calc as (
	select
		_year,
		_month,
		_week,
		_day,
		row_number() over (partition by region, city, _year, _month, _week order by _year, _month, _week, _day asc) as rn_day,
		row_number() over (partition by region, city, _year order by _year, _month, _day asc) as rn_day_year,
		region,
		city,
		yearly_count,
		yearly_count as ytd
	from all_dates
),
all_dates_last_year as (
	select
		date_part('year', db.dt_created) as _year,
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
  join partial_calc pc
  	on date_part('year', db.dt_created) = date_part('year', add_months(current_date, -12))
  		and date_part('month', db.dt_created) = date_part('month', add_months(current_date, -12))
  		and date_part('day', db.dt_created) <= date_part('day', add_months(current_date, -12))
	group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created)
	order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created)
),
year_lag_prev as (
	select distinct
		_year,
		region,
		city,
		ytd
	from partial_calc
),
year_lag as (
	select
		_year,
		region,
		city,
		ytd,
		lag(ytd) over (partition by region, city order by _year) as ytd_lag
	from year_lag_prev
),
year_calc_prev as (
	select
		pc._year,
		pc._month,
		pc._week,
		pc._day,
		pc.rn_day,
		pc.rn_day_year,
		pc.region,
		pc.city,
		pc.yearly_count,
		yl.ytd_lag,
		pc.ytd,
		round(pc.ytd::float / nullif(yl.ytd_lag, 0) - 1.0, 4) as yoy
	from partial_calc pc
	join year_lag yl
		on pc._year = yl._year
			and pc.region = yl.region
			and pc.city = yl.city
),
result as (
	select
		(mycp._year::varchar || lpad(mycp._month::varchar, 2 , '0') || lpad(mycp._day::varchar, 2, '0'))::integer as sk_date,
		case
			when mycp._week = 1
				then to_date(mycp._year::varchar || '0101', 'YYYYMMDD')
			else dateadd(week, mycp._week::integer - 1, to_date(mycp._year::varchar || '0101', 'YYYYMMDD'))::date
		end as sk_week_start_date,
		mycp._year,
		mycp._month,
		mycp._week,
		mycp._day,
		mycp.rn_day,
		mycp.rn_day_year,
		mycp.region,
		mycp.city,
		0 as daily_count,
		0 as prev_weekly_count,
		0 as weekly_count,
		0 as monthly_count,
		mycp.yearly_count,
		0 as wow,
		0 as mtd_lag,
		0 as mtd,
		mycp.ytd_lag,
		mycp.ytd,
		0 as mom,
		coalesce(round((mycp.ytd / nullif(lyc._count, 0)::float) - 1.0, 4), mycp.yoy) as yoy
	from year_calc_prev mycp
	left join all_dates_last_year lyc
		on mycp._year = lyc._year + 1
			and mycp.region = lyc.region
			and mycp.city = lyc.city
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