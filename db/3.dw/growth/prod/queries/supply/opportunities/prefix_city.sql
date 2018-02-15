with all_dates_prev as (
	select distinct
    date_part('year', f.dt_opportunity) as _year,
    date_part('month', f.dt_opportunity) as _month,
    date_part('week', f.dt_opportunity) as _week,
    date_part('day', f.dt_opportunity) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', f.dt_opportunity),
    																date_part('month', f.dt_opportunity),
    																date_part('week', f.dt_opportunity),
    																date_part('day', f.dt_opportunity) order by f.cap_id asc)
    	+ rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', f.dt_opportunity),
    																		date_part('month', f.dt_opportunity),
    																		date_part('week', f.dt_opportunity),
    																		date_part('day', f.dt_opportunity) order by f.cap_id desc)
			- 1 as daily_count,
    rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', f.dt_opportunity),
    																date_part('week', f.dt_opportunity) order by f.cap_id asc)
    	+ rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', f.dt_opportunity),
    																		date_part('week', f.dt_opportunity) order by f.cap_id desc)
			- 1 as weekly_count,
    rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', f.dt_opportunity),
    																date_part('month', f.dt_opportunity) order by f.cap_id asc)
    	+ rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', f.dt_opportunity),
    																		date_part('month', f.dt_opportunity) order by f.cap_id desc)
			- 1 as monthly_count,
    rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', f.dt_opportunity) order by f.cap_id asc)
    	+ rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', f.dt_opportunity) order by f.cap_id desc)
			- 1 as yearly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_opportunity >= '2017-01-01'
		  and f.cap_id != -1
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
  order by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity), date_part('month', f.dt_opportunity), date_part('week', f.dt_opportunity), date_part('day', f.dt_opportunity)
),
all_dates as (
  select distinct
    _year,
    _month,
    _week,
    _day,
    region,
    city,
    max(daily_count) over (partition by city, _day) as daily_count,
    max(weekly_count) over (partition by city, _week) as weekly_count,
    max(monthly_count) over (partition by city, _month) as monthly_count,
    max(yearly_count) over (partition by city, _year) as yearly_count
  from all_dates_prev
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', f.dt_opportunity) as _year,
    date_part('month', f.dt_opportunity) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(f.dt_opportunity) as monthly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_opportunity >= '2017-01-01'
		  and f.cap_id != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where date_part('year', f.dt_opportunity) = date_part('year', add_months(current_date, -1))
  		and date_part('month', f.dt_opportunity) = date_part('month', add_months(current_date, -1))
  		and date_part('day', f.dt_opportunity) <= date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity), date_part('month', f.dt_opportunity)
  order by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity), date_part('month', f.dt_opportunity)
),
all_dates_last_year as (
	select
		date_part('year', f.dt_opportunity) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(f.dt_opportunity) as yearly_count
  from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_opportunity >= '2017-01-01'
		  and f.cap_id != -1
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
  where date_part('year', f.dt_opportunity) = date_part('year', add_months(current_date, -12))
  		and date_part('month', f.dt_opportunity) = date_part('month', add_months(current_date, -12))
  		and date_part('day', f.dt_opportunity) <= date_part('day', add_months(current_date, -12))
	group by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity)
	order by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity)
),
