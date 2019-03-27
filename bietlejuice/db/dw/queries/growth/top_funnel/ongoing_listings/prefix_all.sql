with all_dates as (
  select distinct
    dd.year as _year,
    dd.month as _month,
    dd.calendar_week as _week,
    dd.day as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by dd.year,
    																dd.month,
    																dd.calendar_week,
    																dd.day order by f.sk_house asc)
    	+ dense_rank() over (partition by dd.year,
    																		dd.month,
    																		dd.calendar_week,
    																		dd.day order by f.sk_house desc)
			- 1 as daily_count,
    dense_rank() over (partition by dd.year,
    																dd.calendar_week order by f.sk_house asc)
    	+ dense_rank() over (partition by dd.year,
    																		dd.calendar_week order by f.sk_house desc)
			- 1 as weekly_count,
    dense_rank() over (partition by dd.year,
    																dd.month order by f.sk_house asc)
    	+ dense_rank() over (partition by dd.year,
    																		dd.month order by f.sk_house desc)
			- 1 as monthly_count,
    dense_rank() over (partition by dd.year order by f.sk_house asc)
    	+ dense_rank() over (partition by dd.year order by f.sk_house desc)
			- 1 as yearly_count
	from fact_house_status f
	join dim_date dd
		on dd.sk_date between f.sk_min_status_date and coalesce(f.sk_max_status_date, to_char(current_date - 1, 'YYYYMMDD')::bigint)
			and f.status_history = 'publicado'
	where dd."date" < current_date
  order by 1, 2, 3, 4
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	 	dd.year as _year,
	  dd.month as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_house) as monthly_count
	from fact_house_status f
	join dim_date dd
		on dd.sk_date between f.sk_min_status_date and coalesce(f.sk_max_status_date, to_char(current_date - 1, 'YYYYMMDD')::bigint)
			and f.status_history = 'publicado'
	where dd."date" < current_date
		and dd.year = date_part('year', add_months(current_date, -1))
  	and dd.month = date_part('month', add_months(current_date, -1))
  	and dd.day < date_part('day', current_date)
  group by 1, 2
  order by 1, 2
),
all_dates_last_year as (
	select
	 	dd.year as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_house) as yearly_count
	from fact_house_status f
	join dim_date dd
		on dd.sk_date between f.sk_min_status_date and coalesce(f.sk_max_status_date, to_char(current_date - 1, 'YYYYMMDD')::bigint)
			and f.status_history = 'publicado'
	where dd."date" < current_date
	  and dd.year = date_part('year', add_months(current_date, -12))
  		and ((dd.month = date_part('month', add_months(current_date, -12))
  		      and dd.day < date_part('day', add_months(current_date, -12)))
  		  or dd.month < date_part('month', add_months(current_date, -12))
  		  )
  group by 1
  order by 1
),