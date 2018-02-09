with all_dates_region_week as (
	select
		date_part('year', f.dt_qualified) as _year,
		date_part('month', f.dt_qualified) as _month,
		date_part('week', f.dt_qualified) as _week,
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
	group by coalesce(dr.long_region_name, ''), date_part('year', f.dt_qualified), date_part('month', f.dt_qualified), date_part('week', f.dt_qualified)
	order by coalesce(dr.long_region_name, ''), date_part('year', f.dt_qualified), date_part('month', f.dt_qualified), date_part('week', f.dt_qualified)
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
	join growth.qualifieds_region_day d
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
      and d._week = w._week
),
