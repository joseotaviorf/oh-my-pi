month_lag_prev as (
	select distinct
		_year,
		_month,
		region,
		city,
		monthly_count as mtd
	from all_dates
),
month_lag as (
	select
		_year,
		_month,
		region,
		city,
		mtd,
		lag(mtd) over (partition by region, city order by _year, _month) as mtd_lag
	from month_lag_prev
),
month_calc_prev as (
	select
		ad._year,
		ad._month,
		ad._week,
		ad._day,
		ad.region,
		ad.city,
		ad.monthly_count,
		ml.mtd_lag,
		ad.monthly_count as mtd,
		round((ad.monthly_count / nullif(ml.mtd_lag, 0)::float) - 1.0, 4) as mom
	from all_dates ad
	join month_lag ml
		on ad._year = ml._year
			and ad._month = ml._month
			and ad.region = ml.region
			and ad.city = ml.city
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
		mycp.region,
		mycp.city,
		0 as daily_count,
		0 as prev_weekly_count,
		0 as weekly_count,
		mycp.monthly_count,
		0 as yearly_count,
		0 as wow,
		mycp.mtd_lag,
		mycp.mtd,
		0 as ytd_lag,
		0 as ytd,
		coalesce(round((mycp.mtd / nullif(lmc.monthly_count, 0)::float) - 1.0, 4), mycp.mom) as mom,
		0 as yoy
	from month_calc_prev mycp
	left join all_dates_last_month lmc
		on mycp._year = date_part('year', add_months(to_date(lmc._year::varchar || lpad(lmc._month::varchar, 2, '0') || '01', 'YYYYMMDD'), 1))
			and mycp._month = date_part('month', add_months(to_date(lmc._year::varchar || lpad(lmc._month::varchar, 2, '0') || '01', 'YYYYMMDD'), 1))
			and mycp.region = lmc.region
			and mycp.city = lmc.city
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