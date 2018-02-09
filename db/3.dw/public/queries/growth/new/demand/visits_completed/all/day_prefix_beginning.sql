with all_dates as (
  select
    date_part('year', db.dt_scheduling) as _year,
    date_part('month', db.dt_scheduling) as _month,
    date_part('week', db.dt_scheduling) as _week,
    date_part('day', db.dt_scheduling) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
			and db.dt_scheduling >= '2017-01-01'
			and f.sk_booking != -1
  group by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling), date_part('day', db.dt_scheduling)
  order by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling), date_part('day', db.dt_scheduling)
),
