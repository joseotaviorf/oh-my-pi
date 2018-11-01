with all_dates as (
	select distinct
    date_part('year', dc.ts_signature) as _year,
    date_part('month', dc.ts_signature) as _month,
    date_part('week', dc.ts_signature) as _week,
    date_part('day', dc.ts_signature) as _day,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.ts_signature),
    																date_part('month', dc.ts_signature),
    																date_part('week', dc.ts_signature),
    																date_part('day', dc.ts_signature) order by dc.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.ts_signature),
    																		date_part('month', dc.ts_signature),
    																		date_part('week', dc.ts_signature),
    																		date_part('day', dc.ts_signature) order by dc.sk_contract desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.ts_signature),
    																date_part('week', dc.ts_signature) order by dc.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.ts_signature),
    																		date_part('week', dc.ts_signature) order by dc.sk_contract desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.ts_signature),
    																date_part('month', dc.ts_signature) order by dc.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.ts_signature),
    																		date_part('month', dc.ts_signature) order by dc.sk_contract desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.ts_signature) order by dc.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.ts_signature) order by dc.sk_contract desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.ts_signature >= '2017-01-01' and dc.ts_signature < current_date
			and f.sk_contract != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
  order by coalesce(dr.region_code, ''), date_part('year', dc.ts_signature), date_part('month', dc.ts_signature), date_part('week', dc.ts_signature), date_part('day', dc.ts_signature)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dc.ts_signature) as _year,
    date_part('month', dc.ts_signature) as _month,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as monthly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.ts_signature >= '2017-01-01' and dc.ts_signature < current_date
			and f.sk_contract != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
	where date_part('year', dc.ts_signature) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dc.ts_signature) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dc.ts_signature) < date_part('day', current_date)
 	group by coalesce(dr.region_code, ''), date_part('year', dc.ts_signature), date_part('month', dc.ts_signature)
  order by coalesce(dr.region_code, ''), date_part('year', dc.ts_signature), date_part('month', dc.ts_signature)
),
all_dates_last_year as (
	select
		date_part('year', dc.ts_signature) as _year,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as yearly_count
  from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.ts_signature >= '2017-01-01' and dc.ts_signature < current_date
			and f.sk_contract != -1
  join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
	where date_part('year', dc.ts_signature) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dc.ts_signature) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dc.ts_signature) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dc.ts_signature) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.region_code, ''), date_part('year', dc.ts_signature)
	order by coalesce(dr.region_code, ''), date_part('year', dc.ts_signature)
),
