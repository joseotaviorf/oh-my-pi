with all_dates_all_week as (
	select
		date_part('year', dc.dt_signature) as _year,
		date_part('week', dc.dt_signature) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
	  count(distinct dc.id_contract) as _count
	from fact_liquidity_property_scheduling f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01'
			and f.sk_contract != -1
	group by date_part('year', dc.dt_signature), date_part('week', dc.dt_signature)
	order by date_part('year', dc.dt_signature), date_part('week', dc.dt_signature)
),
all_dates as (
	select
    w._year,
    d._month,
    w._week,
    d._day,
    w.region,
    w.city,
    w._count as weekly_count
	from all_dates_all_week w
	join growth.tenants_all_day d
  	on d._year = w._year
      and d._week = w._week
),
