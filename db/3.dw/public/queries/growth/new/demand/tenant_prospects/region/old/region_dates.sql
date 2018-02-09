drop table if exists growth.tenant_prospects_region_dates;
create table growth.tenant_prospects_region_dates as
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
	from growth.tenant_prospects_region_day
	union all
	select *
	from growth.tenant_prospects_region_week
	union all
	select *
	from growth.tenant_prospects_region_month
	union all
	select *
	from growth.tenant_prospects_region_year
)
group by sk_date, sk_week_start_date, _year, _month, _week, _day, region, city
;