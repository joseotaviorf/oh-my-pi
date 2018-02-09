with all_dates_all_year as (
	select
		date_part('year', dc.dt_signature) as _year,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct dc.id_contract) as _count
	from fact_liquidity_property_scheduling f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01'
			and f.sk_contract != -1
	group by date_part('year', dc.dt_signature)
	order by date_part('year', dc.dt_signature)
),
all_dates as (
	select distinct
    d._year,
    d._month,
    w._week,
    d._day,
    d.region,
    d.city,
    y._count as yearly_count
	from growth.tenants_all_day d
	join growth.tenants_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_year y
  	on d._year = y._year
),
