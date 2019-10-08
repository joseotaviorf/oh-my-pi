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
		on dd.sk_date between fhs.sk_status_start_date and coalesce(to_char(to_date(nullif(fhs.sk_status_end_date, -1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint)
left join dim_house_listing dh
  on fhs.sk_house_listing = dh.sk_house_listing
),
all_dates as (
	select distinct
    f.year as _year,
    f.month as _month,
    f.calendar_week as _week,
    f.day as _day,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    f.year,
    																f.month,
    																f.calendar_week,
    																f.day order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  f.year,
    																		f.month,
    																		f.calendar_week,
    																		f.day order by f.sk_house_listing desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    f.year,
    																f.calendar_week order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  f.year,
    																		f.calendar_week order by f.sk_house_listing desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    f.year,
    																f.month order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  f.year,
    																		f.month order by f.sk_house_listing desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    f.year order by f.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  f.year order by f.sk_house_listing desc)
			- 1 as yearly_count
	from fact_house_listing_status_filter f
	left join dim_region dr
		on f.sk_region = dr.sk_region
	where f."date" < current_date and f.status_history = 'publicado'
  order by 5, 1, 2, 3, 4
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    f.year as _year,
    f.month as _month,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_house_listing) as monthly_count
	from fact_house_listing_status_filter f
	left join dim_region dr
		on f.sk_region = dr.sk_region
	where f."date" < current_date and f.status_history = 'publicado'
		and f.year = date_part('year', add_months(current_date, -1))
  	and f.month = date_part('month', add_months(current_date, -1))
  	and f.day < date_part('day', current_date)
 	group by 3, 1, 2
  order by 3, 1, 2
),
all_dates_last_year as (
	select
		f.year as _year,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_house_listing) as yearly_count
  from fact_house_listing_status_filter f
	left join dim_region dr
		on f.sk_region = dr.sk_region
	where f."date" < current_date and f.status_history = 'publicado'
		and f.year = date_part('year', add_months(current_date, -12))
  		and ((f.month = date_part('month', add_months(current_date, -12))
  		      and f.day < date_part('day', add_months(current_date, -12)))
  		  or f.month < date_part('month', add_months(current_date, -12))
  		  )
	group by 2, 1
	order by 2, 1
),
