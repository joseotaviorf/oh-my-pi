with all_dates_all_month as (
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
  group by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
  order by date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
),
all_dates as (
	select distinct
    d._year,
    d._month,
    w._week,
    d._day,
    d.region,
    d.city,
    m._count as monthly_count
	from growth.visitors_all_day d
	join growth.visitors_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_month m
  	on d._year = m._year
    	and d._month = m._month
),
