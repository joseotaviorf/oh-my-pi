with all_dates_region_month as (
	select
    date_part('year', dc.dt_signature) as _year,
    date_part('month', dc.dt_signature) as _month,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as _count
	from fact_liquidity_property_scheduling f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01'
			and f.sk_contract != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
 	group by coalesce(dr.long_region_name, ''), date_part('year', dc.dt_signature), date_part('month', dc.dt_signature)
  order by coalesce(dr.long_region_name, ''), date_part('year', dc.dt_signature), date_part('month', dc.dt_signature)
),
all_dates as (
	select distinct
    m._year,
    m._month,
    w._week,
    d._day,
    m.region,
    m.city,
    m._count as monthly_count
	from growth.tenants_region_day d
	join growth.tenants_region_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
	join all_dates_region_month m
  	on d._year = m._year
    	and d._month = m._month
),
