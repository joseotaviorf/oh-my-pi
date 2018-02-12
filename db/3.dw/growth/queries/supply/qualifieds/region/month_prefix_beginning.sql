with all_dates_region_month as (
	select
    date_part('year', f.dt_qualified) as _year,
    date_part('month', f.dt_qualified) as _month,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(f.dt_qualified) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_qualified >= '2017-01-01'
		  and f.cap_id != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
 	group by coalesce(dr.long_region_name, ''), date_part('year', f.dt_qualified), date_part('month', f.dt_qualified)
  order by coalesce(dr.long_region_name, ''), date_part('year', f.dt_qualified), date_part('month', f.dt_qualified)
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
	from growth.qualifieds_region_day d
	join growth.qualifieds_region_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
	join all_dates_region_month m
  	on d._year = m._year
    	and d._month = m._month
),
