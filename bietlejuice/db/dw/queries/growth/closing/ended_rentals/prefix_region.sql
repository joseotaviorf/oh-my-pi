with all_dates as (
	select distinct
    date_part('year', dc.dt_contract_annulment) as _year,
    date_part('month', dc.dt_contract_annulment) as _month,
    date_part('week', dc.dt_contract_annulment) as _week,
    date_part('day', dc.dt_contract_annulment) as _day,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_contract_annulment),
    																date_part('month', dc.dt_contract_annulment),
    																date_part('week', dc.dt_contract_annulment),
    																date_part('day', dc.dt_contract_annulment) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_contract_annulment),
    																		date_part('month', dc.dt_contract_annulment),
    																		date_part('week', dc.dt_contract_annulment),
    																		date_part('day', dc.dt_contract_annulment) order by dc.id_contract desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_contract_annulment),
    																date_part('week', dc.dt_contract_annulment) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_contract_annulment),
    																		date_part('week', dc.dt_contract_annulment) order by dc.id_contract desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_contract_annulment),
    																date_part('month', dc.dt_contract_annulment) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_contract_annulment),
    																		date_part('month', dc.dt_contract_annulment) order by dc.id_contract desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dc.dt_contract_annulment) order by dc.id_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dc.dt_contract_annulment) order by dc.id_contract desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_contract_annulment >= '2017-01-01' and dc.dt_contract_annulment < current_date
			and f.sk_contract != -1
			and dc.status != 'Cancelado'
	left join dim_region dr
		on f.sk_region = dr.sk_region
  order by 5, 1, 2, 3, 4
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dc.dt_contract_annulment) as _year,
    date_part('month', dc.dt_contract_annulment) as _month,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as monthly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_contract_annulment >= '2017-01-01' and dc.dt_contract_annulment < current_date
			and f.sk_contract != -1
			and dc.status != 'Cancelado'
	left join dim_region dr
		on f.sk_region = dr.sk_region
	where date_part('year', dc.dt_contract_annulment) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dc.dt_contract_annulment) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dc.dt_contract_annulment) < date_part('day', current_date)
 	group by 3, 1, 2
  order by 3, 1, 2
),
all_dates_last_year as (
	select
		date_part('year', dc.dt_contract_annulment) as _year,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as yearly_count
  from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_contract_annulment >= '2017-01-01' and dc.dt_contract_annulment < current_date
			and f.sk_contract != -1
			and dc.status != 'Cancelado'
  left join dim_region dr
		on f.sk_region = dr.sk_region
	where date_part('year', dc.dt_contract_annulment) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dc.dt_contract_annulment) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dc.dt_contract_annulment) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dc.dt_contract_annulment) < date_part('month', add_months(current_date, -12))
  		  )
	group by 2, 1
	order by 2, 1
),
