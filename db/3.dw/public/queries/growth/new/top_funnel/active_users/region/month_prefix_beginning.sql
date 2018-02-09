with all_dates_region_month as (
	select
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
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
 	group by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created)
  order by coalesce(dr.long_region_name, ''), date_part('year', db.dt_created), date_part('month', db.dt_created)
),
all_dates as (
	select distinct
    m._year,
    m._month,
    w._week,
    d._day,
    m.region,
    m.city,
    m._count as monthly_count
	from growth.tenant_prospects_region_day d
	join growth.tenant_prospects_region_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
	join all_dates_region_month m
  	on d._year = m._year
    	and d._month = m._month
),
