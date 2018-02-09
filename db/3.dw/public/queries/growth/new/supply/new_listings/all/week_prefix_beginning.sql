with all_dates_all_week as (
	select
		date_part('year', dp.publication_date) as _year,
		date_part('week', dp.publication_date) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
	  count(distinct dp.sk_property) as _count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01'
		  and f.sk_property != -1
	group by date_part('year', dp.publication_date), date_part('week', dp.publication_date)
	order by date_part('year', dp.publication_date), date_part('week', dp.publication_date)
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
	join growth.new_listings_all_day d
  	on d._year = w._year
      and d._week = w._week
),
