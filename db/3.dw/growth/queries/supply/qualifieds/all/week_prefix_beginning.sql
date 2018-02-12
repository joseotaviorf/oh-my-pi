with all_dates_all_week as (
	select
		date_part('year', f.dt_qualified) as _year,
		date_part('week', f.dt_qualified) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
	  count(f.dt_qualified) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_qualified >= '2017-01-01'
		  and f.cap_id != -1
	group by date_part('year', f.dt_qualified), date_part('week', f.dt_qualified)
	order by date_part('year', f.dt_qualified), date_part('week', f.dt_qualified)
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
	from all_dates_all_week w
	join growth.qualifieds_all_day d
  	on d._year = w._year
      and d._week = w._week
),
