all_dates_last_month as (
	select
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
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
	join partial_calc pc
  	on date_part('year', db.dt_created) = date_part('year', add_months(current_date, -1))
  		and date_part('month', db.dt_created) = date_part('month', add_months(current_date, -1))
  		and date_part('day', db.dt_created) <= date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created)
  order by coalesce(dr.city_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created)
),