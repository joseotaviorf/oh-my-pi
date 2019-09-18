with
fact_house_listing_status_filter as (
-- new step so we can filter last version and also last status (in case there are two status in the same day)
select
    fhs.*,
    dd.date,
    dd.year,
    dd.month,
    dd.calendar_week,
    dd.day
from fact_house_listing_status fhs
join dim_date dd
    on dd.sk_date between fhs.sk_status_start_date and coalesce(to_char(to_date(fhs.sk_status_end_date, 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint)
left join dim_house_listing dh
  on fhs.sk_house_listing = dh.sk_house_listing
),
all_dates as (
  select distinct
    f.year as _year,
    f.month as _month,
    f.calendar_week as _week,
    f.day as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by f.year,
    																f.month,
    																f.calendar_week,
    																f.day order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by f.year,
    																		f.month,
    																		f.calendar_week,
    																		f.day order by f.sk_house_listing desc)
			- 1 as daily_count,
    dense_rank() over (partition by f.year,
    																f.calendar_week order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by f.year,
    																		f.calendar_week order by f.sk_house_listing desc)
			- 1 as weekly_count,
    dense_rank() over (partition by f.year,
    																f.month order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by f.year,
    																		f.month order by f.sk_house_listing desc)
			- 1 as monthly_count,
    dense_rank() over (partition by f.year order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by f.year order by f.sk_house_listing desc)
			- 1 as yearly_count
	from fact_house_listing_status_filter f
	where f."date" < current_date
	  and f.status_history = 'publicado'
  order by 1, 2, 3, 4
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	  year as _year,
	  month as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_house_listing) as monthly_count
	from fact_house_listing_status_filter f
	where f."date" < current_date
	  and f.status_history = 'publicado'
	  and f.year = date_part('year', add_months(current_date, -1))
  	  and f.month = date_part('month', add_months(current_date, -1))
  	  and f.day < date_part('day', current_date)
  group by 1, 2
  order by 1, 2
),
all_dates_last_year as (
	select
	   year as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_house_listing) as yearly_count
	from fact_house_listing_status_filter f
	where f."date" < current_date and f.status_history = 'publicado'
	  and f.year = date_part('year', add_months(current_date, -12))
  		and ((f.month = date_part('month', add_months(current_date, -12))
  		      and f.day < date_part('day', add_months(current_date, -12)))
  		  or f.month < date_part('month', add_months(current_date, -12))
  		  )
  group by 1
  order by 1
),
