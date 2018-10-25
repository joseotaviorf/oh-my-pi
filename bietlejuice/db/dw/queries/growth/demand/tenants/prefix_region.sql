with all_dates as (
	select distinct
    date_part('year', dc.dt_signature) as _year,
    date_part('month', dc.dt_signature) as _month,
    date_part('week', dc.dt_signature) as _week,
    date_part('day', dc.dt_signature) as _day,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_signature),
    																date_part('month', dc.dt_signature),
    																date_part('week', dc.dt_signature),
    																date_part('day', dc.dt_signature) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_signature),
    																		date_part('month', dc.dt_signature),
    																		date_part('week', dc.dt_signature),
    																		date_part('day', dc.dt_signature) order by dc.id_contract desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_signature),
    																date_part('week', dc.dt_signature) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_signature),
    																		date_part('week', dc.dt_signature) order by dc.id_contract desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_signature),
    																date_part('month', dc.dt_signature) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_signature),
    																		date_part('month', dc.dt_signature) order by dc.id_contract desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_signature) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_signature) order by dc.id_contract desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01' and dc.dt_signature < current_date
			and f.sk_contract != -1
	join dim_house_listing dpr
		on f.sk_house_listing = dpr.sk_house_listing
	left join dim_region dr
		on dpr.regiao_id = dr.id
  order by coalesce(dr.region_code, ''), date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dc.dt_signature) as _year,
    date_part('month', dc.dt_signature) as _month,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as monthly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01' and dc.dt_signature < current_date
			and f.sk_contract != -1
	join dim_house_listing dpr
  	on f.sk_house_listing = dpr.sk_house_listing
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where date_part('year', dc.dt_signature) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dc.dt_signature) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dc.dt_signature) < date_part('day', current_date)
 	group by coalesce(dr.region_code, ''), date_part('year', dc.dt_signature), date_part('month', dc.dt_signature)
  order by coalesce(dr.region_code, ''), date_part('year', dc.dt_signature), date_part('month', dc.dt_signature)
),
all_dates_last_year as (
	select
		date_part('year', dc.dt_signature) as _year,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as yearly_count
  from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01' and dc.dt_signature < current_date
			and f.sk_contract != -1
  join dim_house_listing dpr
  	on f.sk_house_listing = dpr.sk_house_listing
  left join dim_region dr
  	on dpr.regiao_id = dr.id
	where date_part('year', dc.dt_signature) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dc.dt_signature) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dc.dt_signature) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dc.dt_signature) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.region_code, ''), date_part('year', dc.dt_signature)
	order by coalesce(dr.region_code, ''), date_part('year', dc.dt_signature)
),
