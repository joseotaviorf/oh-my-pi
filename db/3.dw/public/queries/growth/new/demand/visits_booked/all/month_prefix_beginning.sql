with all_dates_all_month as (
	select
	 	date_part('year', db.dt_created) as _year,
	  date_part('month', db.dt_created) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.reason_category != 'Reschedule'
			and db.dt_created >= '2017-01-01'
			and f.sk_booking != -1
  group by date_part('year', db.dt_created), date_part('month', db.dt_created)
  order by date_part('year', db.dt_created), date_part('month', db.dt_created)
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
	from growth.visits_booked_all_day d
	join growth.visits_booked_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_month m
  	on d._year = m._year
    	and d._month = m._month
),
