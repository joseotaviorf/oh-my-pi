with all_dates_region_week as (
	select
		date_part('year', db.dt_created) as _year,
		date_part('month', db.dt_created) as _month,
		date_part('week', db.dt_created) as _week,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_user_visitor) as _count
  from fact_liquidity_property_scheduling f
  join dim_booking db
    on f.sk_booking = db.sk_booking
    	and f.sk_booking != -1
    	and db.dt_created is not null
    	and db.dt_created >= '2017-01-01'
  join dim_property dpr
    on f.sk_property = dpr.sk_property
  left join dim_region dr
    on dpr.regiao_id = dr.id
	group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created)
	order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created)
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
	join growth.tenant_prospects_region_day d
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
      and d._week = w._week
),
