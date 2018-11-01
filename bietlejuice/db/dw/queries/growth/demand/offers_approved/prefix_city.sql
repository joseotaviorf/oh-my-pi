with all_dates as (
	select distinct
    date_part('year', dof.dt_analysis) as _year,
    date_part('month', dof.dt_analysis) as _month,
    date_part('week', dof.dt_analysis) as _week,
    date_part('day', dof.dt_analysis) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_analysis),
    																date_part('month', dof.dt_analysis),
    																date_part('week', dof.dt_analysis),
    																date_part('day', dof.dt_analysis) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_analysis),
    																		date_part('month', dof.dt_analysis),
    																		date_part('week', dof.dt_analysis),
    																		date_part('day', dof.dt_analysis) order by dof.sk_offer desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_analysis),
    																date_part('week', dof.dt_analysis) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_analysis),
    																		date_part('week', dof.dt_analysis) order by dof.sk_offer desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_analysis),
    																date_part('month', dof.dt_analysis) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_analysis),
    																		date_part('month', dof.dt_analysis) order by dof.sk_offer desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_analysis) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_analysis) order by dof.sk_offer desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_analysis between '2017-01-01' and current_date - 1
			and dof.status = 'Aprovada'
			and f.sk_offer != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
  order by 6, 1, 2, 3, 4
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dof.dt_analysis) as _year,
    date_part('month', dof.dt_analysis) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct dof.sk_offer) as monthly_count
	from fact_demand f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_analysis between '2017-01-01' and current_date - 1
			and dof.status = 'Aprovada'
			and f.sk_offer != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
	where date_part('year', dof.dt_analysis) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dof.dt_analysis) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dof.dt_analysis) < date_part('day', current_date)
 	group by 4, 1, 2
  order by 4, 1, 2
),
all_dates_last_year as (
	select
		date_part('year', dof.dt_analysis) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct dof.sk_offer) as yearly_count
  from fact_demand f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_analysis between '2017-01-01' and current_date - 1
			and dof.status = 'Aprovada'
			and f.sk_offer != -1
  join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
	where date_part('year', dof.dt_analysis) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dof.dt_analysis) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dof.dt_analysis) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dof.dt_analysis) < date_part('month', add_months(current_date, -12))
  		  )
	group by 3, 1
	order by 3, 1
),
