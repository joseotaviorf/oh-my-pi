with all_dates_city_week as (
	select
		date_part('year', f.dt_contact) as _year,
		date_part('week', f.dt_contact) as _week,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(f.dt_contact) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_contact >= '2017-01-01'
		  and f.cap_id != -1
  join dim_property dpr
    on f.sk_property = dpr.sk_property
  left join dim_region dr
    on dpr.regiao_id = dr.id
	group by coalesce(dr.city_name, ''), date_part('year', f.dt_contact), date_part('week', f.dt_contact)
	order by coalesce(dr.city_name, ''), date_part('year', f.dt_contact), date_part('week', f.dt_contact)
),
all_dates as (
	select
    w._year,
    d._month,
    w._week,
    d._day,
    w.region,
    w.city,
    w._count as weekly_count
	from all_dates_city_week w
	join growth.leads_city_day d
  	on d._year = w._year
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
),
