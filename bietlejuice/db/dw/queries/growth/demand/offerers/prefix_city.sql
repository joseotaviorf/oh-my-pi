with all_dates as (
	select distinct
    date_part('year', dof.dt_first_sent) as _year,
    date_part('month', dof.dt_first_sent) as _month,
    date_part('week', dof.dt_first_sent) as _week,
    date_part('day', dof.dt_first_sent) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_first_sent),
    																date_part('month', dof.dt_first_sent),
    																date_part('week', dof.dt_first_sent),
    																date_part('day', dof.dt_first_sent) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_first_sent),
    																		date_part('month', dof.dt_first_sent),
    																		date_part('week', dof.dt_first_sent),
    																		date_part('day', dof.dt_first_sent) order by f.sk_client desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_first_sent),
    																date_part('week', dof.dt_first_sent) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_first_sent),
    																		date_part('week', dof.dt_first_sent) order by f.sk_client desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_first_sent),
    																date_part('month', dof.dt_first_sent) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_first_sent),
    																		date_part('month', dof.dt_first_sent) order by f.sk_client desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_first_sent) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_first_sent) order by f.sk_client desc)
			- 1 as yearly_count
	from fact_listing_rent_flows f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.offer_submitted is true
			and dof.dt_first_sent >= '2017-01-01' and dof.dt_first_sent < current_date
			and f.sk_offer != - 1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house_listing
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
  order by coalesce(dr.city_name, ''), date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent), date_part('day', dof.dt_first_sent)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dof.dt_first_sent) as _year,
    date_part('month', dof.dt_first_sent) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_client) as monthly_count
	from fact_listing_rent_flows f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.offer_submitted is true
			and dof.dt_first_sent >= '2017-01-01' and dof.dt_first_sent < current_date
			and f.sk_offer != - 1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house_listing
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
	where date_part('year', dof.dt_first_sent) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dof.dt_first_sent) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dof.dt_first_sent) < date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
  order by coalesce(dr.city_name, ''), date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
),
all_dates_last_year as (
	select
		date_part('year', dof.dt_first_sent) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_client) as yearly_count
  from fact_listing_rent_flows f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.offer_submitted is true
			and dof.dt_first_sent >= '2017-01-01' and dof.dt_first_sent < current_date
			and f.sk_offer != - 1
  join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house_listing
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
	where date_part('year', dof.dt_first_sent) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dof.dt_first_sent) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dof.dt_first_sent) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dof.dt_first_sent) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.city_name, ''), date_part('year', dof.dt_first_sent)
	order by coalesce(dr.city_name, ''), date_part('year', dof.dt_first_sent)
),
