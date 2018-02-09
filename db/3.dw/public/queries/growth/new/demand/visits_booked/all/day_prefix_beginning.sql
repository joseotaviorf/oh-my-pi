with all_dates as (
  select
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
    date_part('week', db.dt_created) as _week,
    date_part('day', db.dt_created) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.reason_category != 'Reschedule'
			and db.dt_created >= '2017-01-01'
			and f.sk_booking != -1
  group by date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
  order by date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
),
