-- Calculates the WoW with the lag count
partial_calc_aux as (
	select
		_year,
		_month,
		_week,
		_day,
		row_number() over (partition by region, city, _year, _month, _week order by _year, _month, _week, _day asc) as rn_day,
		row_number() over (partition by region, city, _year order by _year, _month, _day asc) as rn_day_year,
		region,
		city,
		_count,
		sum(_count) over (partition by region, city, _year, _week) as sum_week
	from all_dates
),
partial_calc_lag_prev as (
	select distinct
		_year,
		_week,
		region,
		city,
		sum_week
	from partial_calc_aux
),
partial_calc_lag as (
	select
		_year,
		_week,
		region,
		city,
		sum_week,
		lag(sum_week) over (partition by region, city, _year, _week order by _year, _week) as sum_prev_week
	from partial_calc_lag_prev
),
partial_calc_prev as (
	select
		pca._year,
		pca._month,
		pca._week,
		pca._day,
		pca.rn_day,
		pca.rn_day_year,
		pca.region,
		pca.city,
		pca._count,
		pcl.sum_prev_week,
		pca.sum_week
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
		rn_day,
		rn_day_year,
		region,
		city,
		_count,
		sum_prev_week,
		sum_week,
		round((sum_week::float / sum_prev_week::float) - 1.0, 4) as wow,
		sum(_count) over (partition by region, city, _year, _month) as mtd,
		sum(_count) over (partition by region, city, _year) as ytd
	from partial_calc_prev
),
-- Gets the lag mtd and ytd to calculate later the MoM and YoY.
month_lag_prev as (
	select distinct
		_year,
		_month,
		region,
		city,
		mtd
	from partial_calc
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
month_year_calc_prev as (
	select
		pc._year,
		pc._month,
		pc._week,
		pc._day,
		pc.rn_day,
		pc.rn_day_year,
		pc.region,
		pc.city,
		pc._count,
		pc.sum_prev_week,
		pc.sum_week,
		pc.wow,
		ml.mtd_lag,
		pc.mtd,
		yl.ytd_lag,
		pc.ytd,
		round(pc.mtd::float / nullif(ml.mtd_lag, 0) - 1.0, 4) as mom,
		round(pc.ytd::float / nullif(yl.ytd_lag, 0) - 1.0, 4) as yoy
	from partial_calc pc
	join month_lag ml
		on pc._year = ml._year
			and pc._month = ml._month
			and pc.region = ml.region
			and pc.city = ml.city
	join year_lag yl
		on pc._year = yl._year
			and pc.region = yl.region
			and pc.city = yl.city
),
-- This CTE is necessary because we need to sort the weeks for they start on '1'.
-- That way it gets easier to calculate MoM and YoY of the current month (we need to sum the values until the current
-- week).
this_month_calc as (
	select distinct
		_year,
		_month,
		sum(_count) over (partition by _year, _month, region, city) as sum_count,
		region,
		city,
		max(rn_day) over (partition by _year, _month, region, city) as max_rn_day
	from month_year_calc_prev
	where date_part('year', current_date) = _year
		and date_part('month', current_date) = _month
),
last_month_calc as (
	select distinct
		tmc._year,
		tmc._month,
		tmc.region,
		tmc.city,
		round(sum_count::float / nullif((sum(mycp._count) over (partition by mycp.region, mycp.city))::float, 0) - 1.0, 4) as mom
	from month_year_calc_prev mycp
	join this_month_calc tmc
		on add_months(to_date(mycp._year::varchar || lpad(mycp._month::varchar, 2, '0') || '01', 'YYYYMMDD'), 1)::date = to_date(tmc._year::varchar || lpad(tmc._month::varchar, 2, '0') || '01', 'YYYYMMDD')::date
			and mycp.region = tmc.region
			and mycp.city = tmc.city
			and mycp.rn_day <= tmc.max_rn_day
),
this_year_calc as (
	select distinct
		_year,
		sum(_count) over (partition by _year, region, city) as sum_count,
		region,
		city,
		max(rn_day_year) over (partition by _year, region, city) as max_rn_day
	from month_year_calc_prev
	where date_part('year', current_date) = _year
),
last_year_calc as (
	select distinct
		tyc._year,
		tyc.region,
		tyc.city,
		sum(mycp._count) over (partition by mycp.region, mycp.city),
		round(sum_count::float / nullif((sum(mycp._count) over (partition by mycp.region, mycp.city))::float, 0) - 1.0, 4) as yoy
	from month_year_calc_prev mycp
	join this_year_calc tyc
		on mycp._year + 1 = tyc._year
			and mycp.region = tyc.region
			and mycp.city = tyc.city
			and mycp.rn_day_year <= tyc.max_rn_day
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
		mycp._count,
		mycp.sum_prev_week,
		mycp.sum_week,
		mycp.wow,
		mycp.mtd_lag,
		mycp.mtd,
		mycp.ytd_lag,
		mycp.ytd,
		coalesce(lmc.mom, mycp.mom) as mom,
		coalesce(lyc.yoy, mycp.yoy) as yoy
	from month_year_calc_prev mycp
	left join last_month_calc lmc
		on mycp._year = lmc._year
			and mycp._month = lmc._month
			and mycp.region = lmc.region
			and mycp.city = lmc.city
	left join last_year_calc lyc
		on mycp._year = lyc._year
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
	_count,
	sum_prev_week,
	sum_week,
	wow,
	mtd,
	ytd,
	mom,
	yoy
from result
