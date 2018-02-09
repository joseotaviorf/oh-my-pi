with all_dates_city_year as (
	select
		date_part('year', db.dt_created) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct db.id_booking) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.reason_category != 'Reschedule'
			and db.dt_created >= '2017-01-01'
			and f.sk_booking != -1
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
	group by coalesce(dr.city_name, ''), date_part('year', db.dt_created)
	order by coalesce(dr.city_name, ''), date_part('year', db.dt_created)
),
all_dates as (
	select distinct
    y._year,
    d._month,
    w._week,
    d._day,
    y.region,
    y.city,
    y._count as yearly_count
	from growth.visits_booked_city_day d
	join growth.visits_booked_city_week w
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_city_year y
  	on d.city = y.city
  		and d.region = y.region
  		and d._year = y._year
),
