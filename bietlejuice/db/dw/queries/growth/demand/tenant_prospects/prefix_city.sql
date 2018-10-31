with all_dates as (
	select distinct
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
    date_part('week', db.dt_created) as _week,
    date_part('day', db.dt_created) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created),
    																date_part('month', db.dt_created),
    																date_part('week', db.dt_created),
    																date_part('day', db.dt_created) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', db.dt_created),
    																		date_part('month', db.dt_created),
    																		date_part('week', db.dt_created),
    																		date_part('day', db.dt_created) order by f.sk_client desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created),
    																date_part('week', db.dt_created) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', db.dt_created),
    																		date_part('week', db.dt_created) order by f.sk_client desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created),
    																date_part('month', db.dt_created) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', db.dt_created),
    																		date_part('month', db.dt_created) order by f.sk_client desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', db.dt_created) order by f.sk_client desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and f.sk_booking != -1
  		and db.dt_created >= '2017-01-01' and db.dt_created < current_date
	join dim_house_listing dpr
		on f.sk_house_listing = dpr.sk_house_listing
	left join dim_region dr
		on dpr.regiao_id = dr.id
  order by coalesce(dr.city_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_client) as monthly_count
	from fact_demand f
	join dim_booking db
  	on f.sk_booking = db.sk_booking
  		and f.sk_booking != -1
  		and db.dt_created >= '2017-01-01' and db.dt_created < current_date
	join dim_house_listing dpr
  	on f.sk_house_listing = dpr.sk_house_listing
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where date_part('year', db.dt_created) = date_part('year', add_months(current_date, -1))
  		and date_part('month', db.dt_created) = date_part('month', add_months(current_date, -1))
  		and date_part('day', db.dt_created) < date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created)
  order by coalesce(dr.city_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created)
),
all_dates_last_year as (
	select
		date_part('year', db.dt_created) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_client) as yearly_count
  from fact_demand f
  join dim_booking db
  	on f.sk_booking = db.sk_booking
  		and f.sk_booking != -1
  		and db.dt_created >= '2017-01-01' and db.dt_created < current_date
  join dim_house_listing dpr
  	on f.sk_house_listing = dpr.sk_house_listing
  left join dim_region dr
  	on dpr.regiao_id = dr.id
	where date_part('year', db.dt_created) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', db.dt_created) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', db.dt_created) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', db.dt_created) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.city_name, ''), date_part('year', db.dt_created)
	order by coalesce(dr.city_name, ''), date_part('year', db.dt_created)
),
