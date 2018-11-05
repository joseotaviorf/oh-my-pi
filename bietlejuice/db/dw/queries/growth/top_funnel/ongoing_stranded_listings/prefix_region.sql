with all_dates as (
	select distinct
    dd.year as _year,
    dd.month as _month,
    dd.calendar_week as _week,
    dd.day as _day,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    dd.year,
    																dd.month,
    																dd.calendar_week,
    																dd.day order by f.sk_house asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  dd.year,
    																		dd.month,
    																		dd.calendar_week,
    																		dd.day order by f.sk_house desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    dd.year,
    																dd.calendar_week order by f.sk_house asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  dd.year,
    																		dd.calendar_week order by f.sk_house desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    dd.year,
    																dd.month order by f.sk_house asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  dd.year,
    																		dd.month order by f.sk_house desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    dd.year order by f.sk_house asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  dd.year order by f.sk_house desc)
			- 1 as yearly_count
	from fact_house_status f
	join dim_date dd
		on dd.sk_date between f.sk_min_version_status_date and coalesce(f.sk_max_status_date, to_char(current_date - 1, 'YYYYMMDD')::bigint)
			and datediff('day', to_date(f.sk_min_version_status_date, 'YYYYMMDD')::date, to_date(dd.sk_date, 'YYYYMMDD')) >= 84
			and f.status_history = 'publicado'
	left join dim_region dr
		on f.sk_region = dr.sk_region
	where dd."date" < current_date
  order by 5, 1, 2, 3, 4
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    dd.year as _year,
    dd.month as _month,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_house) as monthly_count
	from fact_house_status f
	join dim_date dd
		on dd.sk_date between f.sk_min_version_status_date and coalesce(f.sk_max_status_date, to_char(current_date - 1, 'YYYYMMDD')::bigint)
			and datediff('day', to_date(f.sk_min_version_status_date, 'YYYYMMDD')::date, to_date(dd.sk_date, 'YYYYMMDD')) >= 84
			and f.status_history = 'publicado'
	left join dim_region dr
		on f.sk_region = dr.sk_region
	where dd."date" < current_date
		and dd.year = date_part('year', add_months(current_date, -1))
  	and dd.month = date_part('month', add_months(current_date, -1))
  	and dd.day < date_part('day', current_date)
 	group by 3, 1, 2
  order by 3, 1, 2
),
all_dates_last_year as (
	select
		dd.year as _year,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_house) as yearly_count
  from fact_house_status f
	join dim_date dd
		on dd.sk_date between f.sk_min_version_status_date and coalesce(f.sk_max_status_date, to_char(current_date - 1, 'YYYYMMDD')::bigint)
			and datediff('day', to_date(f.sk_min_version_status_date, 'YYYYMMDD')::date, to_date(dd.sk_date, 'YYYYMMDD')) >= 84
			and f.status_history = 'publicado'
	left join dim_region dr
		on f.sk_region = dr.sk_region
	where dd."date" < current_date
		and dd.year = date_part('year', add_months(current_date, -12))
  		and ((dd.month = date_part('month', add_months(current_date, -12))
  		      and dd.day < date_part('day', add_months(current_date, -12)))
  		  or dd.month < date_part('month', add_months(current_date, -12))
  		  )
	group by 2, 1
	order by 2, 1
),
