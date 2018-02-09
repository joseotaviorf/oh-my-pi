with all_dates_region_week as (
	select
		date_part('year', db.dt_scheduling) as _year,
		date_part('month', db.dt_scheduling) as _month,
		date_part('week', db.dt_scheduling) as _week,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
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
	group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling)
	order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling)
),
all_dates as (
	select
    w._year,
    d._month,
    w._week,
    d._day,
    w.city,
    w.region,
    w._count as weekly_count
	from all_dates_region_week w
	join growth.visits_completed_region_day d
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
      and d._week = w._week
),
