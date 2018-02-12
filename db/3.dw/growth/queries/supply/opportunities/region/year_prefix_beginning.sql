with all_dates_region_year as (
	select
		date_part('year', f.dt_opportunity) as _year,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
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
	group by coalesce(dr.long_region_name, ''), date_part('year', f.dt_opportunity)
	order by coalesce(dr.long_region_name, ''), date_part('year', f.dt_opportunity)
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
	from growth.opportunities_region_day d
	join growth.opportunities_region_week w
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_region_year y
  	on d.city = y.city
  		and d.region = y.region
  		and d._year = y._year
),
