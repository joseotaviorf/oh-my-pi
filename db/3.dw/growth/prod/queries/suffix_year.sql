year_lag_prev as (
	select distinct
		_year,
		region,
		city,
		yearly_count as ytd
	from all_dates
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
		ad._year,
		ad._month,
		ad._week,
		ad._day,
		ad.region,
		ad.city,
		ad.yearly_count,
		yl.ytd_lag,
		ad.yearly_count as ytd,
		round(ad.yearly_count / nullif(yl.ytd_lag, 0)::float, 4) as yoy
	from all_dates ad
	join year_lag yl
		on ad._year = yl._year
			and ad.region = yl.region
			and ad.city = yl.city
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
		0 as monthly_count,
		mycp.yearly_count,
		0 as wow,
		0 as mtd_lag,
		0 as mtd,
		mycp.ytd_lag,
		mycp.ytd,
		0 as mom,
		coalesce(round(mycp.ytd / nullif(lyc.yearly_count, 0)::float, 4), mycp.yoy) as yoy
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
