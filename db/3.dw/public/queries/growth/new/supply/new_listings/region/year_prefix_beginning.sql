with all_dates_region_year as (
	select
		date_part('year', dp.publication_date) as _year,
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
	group by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date)
	order by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date)
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
	from growth.new_listings_region_day d
	join growth.new_listings_region_week w
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
