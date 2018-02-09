all_dates_last_month as (
	select
	 	date_part('year', dc.dt_signature) as _year,
	  date_part('month', dc.dt_signature) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dc.id_contract) as _count
	from fact_liquidity_property_scheduling f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
			and dc.dt_signature >= '2017-01-01'
			and f.sk_contract != -1
  join partial_calc pc
  	on date_part('year', dc.dt_signature) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dc.dt_signature) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dc.dt_signature) <= date_part('day', current_date)
  group by date_part('year', dc.dt_signature), date_part('month', dc.dt_signature)
  order by date_part('year', dc.dt_signature), date_part('month', dc.dt_signature)
),
