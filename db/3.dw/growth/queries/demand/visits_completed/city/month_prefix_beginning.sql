with all_dates_city_month as (
	select
    date_part('year', db.dt_scheduling) as _year,
    date_part('month', db.dt_scheduling) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
			and db.dt_scheduling >= '2017-01-01'
			and f.sk_booking != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
 	group by coalesce(dr.city_name, ''), date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
  order by coalesce(dr.city_name, ''), date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
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
	from growth.visits_completed_all_day d
	join growth.visits_completed_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
	join all_dates_city_month m
  	on d._year = m._year
    	and d._month = m._month
    	and d.city = m.city
    	and d.region = m.region
),
