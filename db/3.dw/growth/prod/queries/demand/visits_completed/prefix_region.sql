with all_dates as (
	select distinct
    date_part('year', db.dt_scheduling) as _year,
    date_part('month', db.dt_scheduling) as _month,
    date_part('week', db.dt_scheduling) as _week,
    date_part('day', db.dt_scheduling) as _day,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', db.dt_scheduling),
    																date_part('month', db.dt_scheduling),
    																date_part('week', db.dt_scheduling),
    																date_part('day', db.dt_scheduling) order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', db.dt_scheduling),
    																		date_part('month', db.dt_scheduling),
    																		date_part('week', db.dt_scheduling),
    																		date_part('day', db.dt_scheduling) order by db.id_booking desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', db.dt_scheduling),
    																date_part('week', db.dt_scheduling) order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', db.dt_scheduling),
    																		date_part('week', db.dt_scheduling) order by db.id_booking desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', db.dt_scheduling),
    																date_part('month', db.dt_scheduling) order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', db.dt_scheduling),
    																		date_part('month', db.dt_scheduling) order by db.id_booking desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', db.dt_scheduling) order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', db.dt_scheduling) order by db.id_booking desc)
			- 1 as yearly_count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
			and db.dt_scheduling >= '2017-01-01' and db.dt_scheduling < current_date
			and f.sk_booking != -1
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
  order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling), date_part('week', db.dt_scheduling), date_part('day', db.dt_scheduling)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', db.dt_scheduling) as _year,
    date_part('month', db.dt_scheduling) as _month,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct db.id_booking) as monthly_count
	from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
			and db.dt_scheduling >= '2017-01-01' and db.dt_scheduling < current_date
			and f.sk_booking != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where date_part('year', db.dt_scheduling) = date_part('year', add_months(current_date, -1))
  		and date_part('month', db.dt_scheduling) = date_part('month', add_months(current_date, -1))
  		and date_part('day', db.dt_scheduling) < date_part('day', current_date)
 	group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
  order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_scheduling), date_part('month', db.dt_scheduling)
),
all_dates_last_year as (
	select
		date_part('year', db.dt_scheduling) as _year,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct db.id_booking) as yearly_count
  from fact_liquidity_property_scheduling f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
			and db.dt_scheduling >= '2017-01-01' and db.dt_scheduling < current_date
			and f.sk_booking != -1
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
	where date_part('year', db.dt_scheduling) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', db.dt_scheduling) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', db.dt_scheduling) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', db.dt_scheduling) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_scheduling)
	order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_scheduling)
),
