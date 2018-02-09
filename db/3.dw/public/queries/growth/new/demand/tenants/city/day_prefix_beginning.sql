with all_dates as (
	select
    date_part('year', dc.dt_signature) as _year,
    date_part('month', dc.dt_signature) as _month,
    date_part('week', dc.dt_signature) as _week,
    date_part('day', dc.dt_signature) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
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
  group by coalesce(dr.city_name, ''), date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
  order by coalesce(dr.city_name, ''), date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
),
