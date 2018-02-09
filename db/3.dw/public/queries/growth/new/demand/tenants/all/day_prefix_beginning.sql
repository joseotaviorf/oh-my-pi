with all_dates as (
  select
    date_part('year', dc.dt_signature) as _year,
    date_part('month', dc.dt_signature) as _month,
    date_part('week', dc.dt_signature) as _week,
    date_part('day', dc.dt_signature) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    count(distinct dc.id_contract) as _count
	from fact_liquidity_property_scheduling f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01'
			and f.sk_contract != -1
  group by date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
  order by date_part('year', dc.dt_signature), date_part('month', dc.dt_signature), date_part('week', dc.dt_signature), date_part('day', dc.dt_signature)
),
