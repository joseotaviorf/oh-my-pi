with all_dates_region_week as (
	select
		date_part('year', dp.publication_date) as _year,
		date_part('month', dp.publication_date) as _month,
		date_part('week', dp.publication_date) as _week,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dp.sk_property) as _count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01'
		  and f.sk_property != -1
  join dim_property dpr
    on f.sk_property = dpr.sk_property
  left join dim_region dr
    on dpr.regiao_id = dr.id
	group by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date)
	order by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date)
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
	join growth.new_listings_region_day d
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
      and d._week = w._week
),
