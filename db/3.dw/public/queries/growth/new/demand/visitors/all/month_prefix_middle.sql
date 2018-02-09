all_dates_last_month as (
	select
	 	date_part('year', db.dt_scheduling) as _year,
	  date_part('month', db.dt_scheduling) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
			and db.dt_scheduling >= '2017-01-01'
			and f.sk_booking != -1
  join partial_calc pc
  	on date_part('year', db.dt_scheduling) = date_part('year', add_months(current_date, -1))
  		and date_part('month', db.dt_scheduling) = date_part('month', add_months(current_date, -1))
  		and date_part('day', db.dt_scheduling) <= date_part('day', current_date)
  group by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
  order by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
),
