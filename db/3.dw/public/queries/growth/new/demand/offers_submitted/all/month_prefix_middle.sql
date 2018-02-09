all_dates_last_month as (
	select
	 	date_part('year', dof.dt_first_sent) as _year,
	  date_part('month', dof.dt_first_sent) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dof.sk_offer) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_first_sent >= '2017-01-01'
			and f.sk_offer != -1
  join partial_calc pc
  	on date_part('year', dof.dt_first_sent) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dof.dt_first_sent) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dof.dt_first_sent) <= date_part('day', current_date)
  group by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
  order by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
),
