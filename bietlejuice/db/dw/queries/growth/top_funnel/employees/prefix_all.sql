with all_dates as (
	select distinct
		date_part('year', dt_updated) as _year,
		date_part('month', dt_updated) as _month,
		date_part('week', dt_updated) as _week,
		1 as _day,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		dense_rank() over (partition by date_part('year', dt_updated),
    																date_part('month', dt_updated),
    																date_part('week', dt_updated) order by "name" asc)
    	+ dense_rank() over (partition by date_part('year', dt_updated),
    																		date_part('month', dt_updated),
    																		date_part('week', dt_updated) order by "name" desc)
			- 1 as weekly_count,
		dense_rank() over (partition by date_part('year', dt_updated),
    																date_part('month', dt_updated) order by "name" asc)
    	+ dense_rank() over (partition by date_part('year', dt_updated),
    																		date_part('month', dt_updated) order by "name" desc)
			- 1 as monthly_count,
		dense_rank() over (partition by date_part('year', dt_updated) order by "name" asc)
    	+ dense_rank() over (partition by date_part('year', dt_updated) order by "name" desc)
			- 1 as yearly_count
  from growth.employee_base
  where "category" in ('Back-office (offboarding)',
  	'Back-office (onboarding)',
  	'Back-office (ongoing)',
  	'Customer Support (post-sale)',
  	'Customer support (post-sale)',
  	'Collections'
  )
	order by date_part('year', dt_updated), date_part('month', dt_updated), date_part('week', dt_updated)
),
all_dates_last_month as (
	select
		date_part('year', dt_updated) as _year,
		date_part('month', dt_updated) as _month,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct "name") as monthly_count
  from growth.employee_base
  where "category" in ('Back-office (offboarding)',
  	'Back-office (onboarding)',
  	'Back-office (ongoing)',
  	'Customer Support (post-sale)',
  	'Customer support (post-sale)',
  	'Collections'
  )
    and date_part('year', dt_updated) = date_part('year', add_months(current_date, -1))
  	and date_part('month', dt_updated) = date_part('month', add_months(current_date, -1))
  	and date_part('day', dt_updated) < date_part('day', current_date)
  group by date_part('year', dt_updated), date_part('month', dt_updated)
	order by date_part('year', dt_updated), date_part('month', dt_updated)
),
all_dates_last_year as (
	select
		date_part('year', dt_updated) as _year,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct "name") as yearly_count
  from growth.employee_base
  where "category" in ('Back-office (offboarding)',
  	  'Back-office (onboarding)',
  	  'Back-office (ongoing)',
  	  'Customer Support (post-sale)',
  	  'Customer support (post-sale)',
  	  'Collections'
    )
    and date_part('year', dt_updated) = date_part('year', add_months(current_date, -12))
  	and date_part('month', dt_updated) <= date_part('month', add_months(current_date, -12))
  	and date_part('day', dt_updated) <= date_part('day', add_months(current_date, -12))
  group by date_part('year', dt_updated)
	order by date_part('year', dt_updated)
),