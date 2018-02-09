with all_dates_city_month as (
	select
    date_part('year', f.dt_opportunity) as _year,
    date_part('month', f.dt_opportunity) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(f.dt_opportunity) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_opportunity >= '2017-01-01'
		  and f.cap_id != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
 	group by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity), date_part('month', f.dt_opportunity)
  order by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity), date_part('month', f.dt_opportunity)
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
	from growth.opportunities_all_day d
	join growth.opportunities_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
	join all_dates_city_month m
  	on d._year = m._year
    	and d._month = m._month
    	and d.city = m.city
    	and d.region = m.region
),
