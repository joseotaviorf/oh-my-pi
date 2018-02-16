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
	from all_dates
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