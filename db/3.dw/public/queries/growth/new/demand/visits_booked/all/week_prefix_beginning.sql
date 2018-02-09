with all_dates_all_week as (
	select
		date_part('year', db.dt_created) as _year,
		date_part('week', db.dt_created) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
	  count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.reason_category != 'Reschedule'
			and db.dt_created >= '2017-01-01'
			and f.sk_booking != -1
	group by date_part('year', db.dt_created), date_part('week', db.dt_created)
	order by date_part('year', db.dt_created), date_part('week', db.dt_created)
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
	join growth.visits_booked_all_day d
  	on d._year = w._year
      and d._week = w._week
),
