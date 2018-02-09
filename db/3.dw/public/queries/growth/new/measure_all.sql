create table growth.{0}_all as
select
	sk_date,
	sk_week_start_date,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	sum(daily_count) as daily_count,
	sum(prev_weekly_count) as prev_weekly_count,
	sum(weekly_count) as weekly_count,
	sum(monthly_count) as monthly_count,
	sum(yearly_count) as yearly_count,
	sum(wow) as wow,
	sum(mtd) as mtd,
	sum(ytd) as ytd,
	sum(mom) as mom,
	sum(yoy) as yoy
from (
	select *
	from growth.{0}_all_day
	union all
	select *
	from growth.{0}_all_week
	union all
	select *
	from growth.{0}_all_month
	union all
	select *
	from growth.{0}_all_year
	union all
	select *
	from growth.{0}_city_day
	union all
	select *
	from growth.{0}_city_week
	union all
	select *
	from growth.{0}_city_month
	union all
	select *
	from growth.{0}_city_year
	union all
	select *
	from growth.{0}_region_day
	union all
	select *
	from growth.{0}_region_week
	union all
	select *
	from growth.{0}_region_month
	union all
	select *
	from growth.{0}_region_year
)
group by sk_date, sk_week_start_date, _year, _month, _week, _day, region, city
;