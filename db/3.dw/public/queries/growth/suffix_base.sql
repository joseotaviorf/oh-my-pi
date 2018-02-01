-- Calculates the WoW with the lag count
partial_calc as (
	select
		_year,
		_month,
		_week,
		region,
		city,
		concat_month,
		_count,
		lag(_count) over (partition by region, city order by concat_all) as count_prev_week,
		round((_count::float / (lag(_count) over (partition by region, city order by concat_all))::float) - 1.0, 4) as wow,
		sum(_count) over (partition by region, city, concat_month) as mtd,
		sum(_count) over (partition by region, city, _year) as ytd
	from all_dates
),
-- Gets the lag mtd and ytd to calculate later the MoM and YoY.
month_year_lag as (
	select
		_year,
		_month,
		_week,
		region,
		city,
		concat_month,
		count_prev_week,
		_count,
		wow,
		mtd,
		ytd,
		case
			when _month != lag(_month) over (partition by region, city order by concat_month)::float
				then ((lag(mtd) over (partition by region, city order by concat_month))::float)
		  else 0
		end as _mom_lag,
		case
			when _year != lag(_year) over (partition by region, city order by _year)::float
				then ((lag(ytd) over (partition by region, city order by _year))::float)
		  else 0
		end as _yoy_lag
	from partial_calc
),
-- Calculates the MoM and YoY with the MTD and YTD
partial_result as (
	select
		_year,
		_month,
		_week,
		region,
		city,
		count_prev_week,
		_count,
		wow,
		mtd,
		ytd,
		round(mtd::float / nullif((sum(_mom_lag) over (partition by region, city, concat_month)::float), 0) - 1.0, 4) as mom,
		round(ytd::float / nullif((sum(_yoy_lag) over (partition by region, city, _year)::float), 0) - 1.0, 4) as yoy
	from month_year_lag
),
-- This CTE is necessary because we need to sort the weeks for they start on '1'.
-- That way it gets easier to calculate MoM and YoY of the current month (we need to sum the values until the current
-- week).
this_month_calc as (
	select
		_year,
		_month,
		_count,
		region,
		city,
		row_number() over (partition by region, city order by _week) as week_of_month
	from partial_result
	where date_part('year', current_date) = _year
		and date_part('month', current_date) = _month
		and (_week <= date_part('week', date_trunc('week', current_date))
			or (_week > 40 and _month = 1))
),
last_month_calc as (
	select
		_year,
		_month,
		_count,
		region,
		city,
		row_number() over (partition by region, city order by _week) as week_of_month
	from partial_result
	where date_part('month', add_months(current_date, -1)) = _month
		and (date_part('year', current_date) = _year
			or (date_part('month', current_date) = 1 and date_part('year', current_date) - 1 = _year))
),
mom_calc as (
	select
		tmc._year,
		tmc._month,
		tmc.region,
		tmc.city,
		round(sum(tmc._count)::float / nullif(sum(lmc._count)::float, 0) - 1.0, 4) as mom
	from this_month_calc tmc
	join last_month_calc lmc
	  on tmc.week_of_month = lmc.week_of_month
	group by tmc._year, tmc._month, tmc.region, tmc.city
),
this_year_calc as (
	select
		_year,
		_month,
		_count,
		region,
		city,
		row_number() over (partition by region, city order by _month, _week) as week_of_year
	from partial_result
	where date_part('year', current_date) = _year
		and (_week <= date_part('week', date_trunc('week', current_date))
			or (_week > 40 and _month = 1))
),
last_year_calc as (
	select
		_year,
		_month,
		_count,
		_week,
		region,
		city,
		row_number() over (partition by region, city order by _month, _week) as week_of_year
	from partial_result
	where date_part('year', current_date) - 1 = _year
),
yoy_calc as (
	select
		tyc._year,
		tyc._month,
		tyc.region,
		tyc.city,
		sum(tyc._count),
		sum(lyc._count),
		round(sum(tyc._count)::float / nullif(sum(lyc._count)::float, 0) - 1.0, 4) as yoy
	from this_year_calc tyc
	join last_year_calc lyc
	  on tyc.week_of_year = lyc.week_of_year
	group by tyc._year, tyc._month, tyc.region, tyc.city
),
result as (
	select
		case
			when pr._week = 1
				then to_date(pr._year::varchar || '0101', 'YYYYMMDD')
			else dateadd(week, pr._week::integer - 1, to_date(pr._year::varchar || '0101', 'YYYYMMDD'))::date
		end as sk_week_start_date,
		pr._year,
		pr._month,
		pr._week,
		pr.region,
		pr.city,
		pr.count_prev_week,
		pr._count,
		pr.wow,
		pr.mtd,
		pr.ytd,
		coalesce(momc.mom, pr.mom) as mom,
		coalesce(yoyc.yoy, pr.yoy) as yoy
	from partial_result pr
	left join mom_calc momc
		on pr._year = momc._year
			and pr._month = momc._month
			and pr.region = momc.region
			and pr.city = momc.city
	left join yoy_calc yoyc
		on pr._year = yoyc._year
			and pr._month = yoyc._month
			and pr.region = yoyc.region
			and pr.city = yoyc.city
	order by pr._year, pr._week, pr._month
)
select
  (_year::varchar || _month::varchar || _week::varchar)::integer as sk_date,
	(date_part('year', sk_week_start_date)::varchar
		|| lpad(date_part('month', sk_week_start_date)::varchar, 2, '0')
		|| lpad(date_part('day', sk_week_start_date)::varchar, 2, '0'))::integer as sk_week_start_date,
	_year,
	_month,
	_week,
	region,
	city,
	count_prev_week,
	_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy
from result
