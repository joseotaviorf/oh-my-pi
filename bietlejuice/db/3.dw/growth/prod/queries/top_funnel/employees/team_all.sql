create table growth.{0} as
select
	sk_date,
	sk_week_start_date,
	_year,
	_month,
	_week,
	_day,
	'operations'::varchar as team,
	sum(prev_weekly_count) as prev_weekly_count,
	sum(weekly_count) as weekly_count,
	sum(monthly_count) as monthly_count,
	sum(yearly_count) as yearly_count,
	sum(mtd) as mtd,
	sum(ytd) as ytd
from (
	select *
	from growth.{0}_all_week
	union all
	select *
	from growth.{0}_all_month
	union all
	select *
	from growth.{0}_all_year
)
group by sk_date, sk_week_start_date, _year, _month, _week, _day, team
;