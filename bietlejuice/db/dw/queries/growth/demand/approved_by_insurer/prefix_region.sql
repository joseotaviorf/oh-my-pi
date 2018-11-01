with all_dates as (
	select distinct
    date_part('year', dp.dt_proposal_approved) as _year,
    date_part('month', dp.dt_proposal_approved) as _month,
    date_part('week', dp.dt_proposal_approved) as _week,
    date_part('day', dp.dt_proposal_approved) as _day,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dp.dt_proposal_approved),
    																date_part('month', dp.dt_proposal_approved),
    																date_part('week', dp.dt_proposal_approved),
    																date_part('day', dp.dt_proposal_approved) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dp.dt_proposal_approved),
    																		date_part('month', dp.dt_proposal_approved),
    																		date_part('week', dp.dt_proposal_approved),
    																		date_part('day', dp.dt_proposal_approved) order by f.sk_client desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dp.dt_proposal_approved),
    																date_part('week', dp.dt_proposal_approved) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dp.dt_proposal_approved),
    																		date_part('week', dp.dt_proposal_approved) order by f.sk_client desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dp.dt_proposal_approved),
    																date_part('month', dp.dt_proposal_approved) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dp.dt_proposal_approved),
    																		date_part('month', dp.dt_proposal_approved) order by f.sk_client desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dp.dt_proposal_approved) order by f.sk_client asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dp.dt_proposal_approved) order by f.sk_client desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved >= '2017-01-01' and dp.dt_proposal_approved < current_date
			and f.sk_proposal != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
  order by coalesce(dr.region_code, ''), date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved), date_part('week', dp.dt_proposal_approved), date_part('day', dp.dt_proposal_approved)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dp.dt_proposal_approved) as _year,
    date_part('month', dp.dt_proposal_approved) as _month,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_client) as monthly_count
	from fact_demand f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved >= '2017-01-01' and dp.dt_proposal_approved < current_date
			and f.sk_proposal != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	on fhl.sk_region = dr.sk_region
	where date_part('year', dp.dt_proposal_approved) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dp.dt_proposal_approved) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dp.dt_proposal_approved) < date_part('day', current_date)
 	group by coalesce(dr.region_code, ''), date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
  order by coalesce(dr.region_code, ''), date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
),
all_dates_last_year as (
	select
		date_part('year', dp.dt_proposal_approved) as _year,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_client) as yearly_count
  from fact_demand f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved >= '2017-01-01' and dp.dt_proposal_approved < current_date
			and f.sk_proposal != -1
  join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
  left join dim_region dr
  	on fhl.sk_region = dr.sk_region
	where date_part('year', dp.dt_proposal_approved) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dp.dt_proposal_approved) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dp.dt_proposal_approved) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dp.dt_proposal_approved) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.region_code, ''), date_part('year', dp.dt_proposal_approved)
	order by coalesce(dr.region_code, ''), date_part('year', dp.dt_proposal_approved)
),
