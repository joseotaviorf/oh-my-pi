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