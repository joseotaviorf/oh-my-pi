with all_dates as (
	select distinct
    date_part('year', dl.criado_em) as _year,
    date_part('month', dl.criado_em) as _month,
    date_part('week', dl.criado_em) as _week,
    date_part('day', dl.criado_em) as _day,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dl.criado_em),
    																date_part('month', dl.criado_em),
    																date_part('week', dl.criado_em),
    																date_part('day', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dl.criado_em),
    																		date_part('month', dl.criado_em),
    																		date_part('week', dl.criado_em),
    																		date_part('day', dl.criado_em) order by dp.sk_property desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dl.criado_em),
    																date_part('week', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dl.criado_em),
    																		date_part('week', dl.criado_em) order by dp.sk_property desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dl.criado_em),
    																date_part('month', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dl.criado_em),
    																		date_part('month', dl.criado_em) order by dp.sk_property desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.region_code, ''),
                                    date_part('year', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.region_code, ''),
    	                                  date_part('year', dl.criado_em) order by dp.sk_property desc)
			- 1 as yearly_count
	from fact_supply f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and f.sk_property != -1
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	join dim_lead dl
		on f.sk_lead = dl.sk_lead
		  and dl.criado_em >= '2017-01-01' and dl.criado_em < current_date
	where f.acquisition_channel = 'Landing Page Leads'
  order by coalesce(dr.region_code, ''), date_part('year', dl.criado_em), date_part('month', dl.criado_em), date_part('week', dl.criado_em), date_part('day', dl.criado_em)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dl.criado_em) as _year,
    date_part('month', dl.criado_em) as _month,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dp.sk_property) as monthly_count
	from fact_supply f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and f.sk_property != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	join dim_lead dl
		on f.sk_lead = dl.sk_lead
		  and dl.criado_em >= '2017-01-01' and dl.criado_em < current_date
	where date_part('year', dl.criado_em) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dl.criado_em) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dl.criado_em) < date_part('day', current_date)
  		and f.acquisition_channel = 'Landing Page Leads'
 	group by coalesce(dr.region_code, ''), date_part('year', dl.criado_em), date_part('month', dl.criado_em)
  order by coalesce(dr.region_code, ''), date_part('year', dl.criado_em), date_part('month', dl.criado_em)
),
all_dates_last_year as (
	select
		date_part('year', dl.criado_em) as _year,
    coalesce(dr.region_code, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dp.sk_property) as yearly_count
  from fact_supply f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and f.sk_property != -1
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
  join dim_lead dl
		on f.sk_lead = dl.sk_lead
		  and dl.criado_em >= '2017-01-01' and dl.criado_em < current_date
  where date_part('year', dl.criado_em) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dl.criado_em) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dl.criado_em) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dl.criado_em) < date_part('month', add_months(current_date, -12))
  		  )
  		and f.acquisition_channel = 'Landing Page Leads'
	group by coalesce(dr.region_code, ''), date_part('year', dl.criado_em)
	order by coalesce(dr.region_code, ''), date_part('year', dl.criado_em)
),
