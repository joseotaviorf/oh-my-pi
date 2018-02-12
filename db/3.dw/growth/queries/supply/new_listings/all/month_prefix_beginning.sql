with all_dates_all_month as (
	select
	 	date_part('year', dp.publication_date) as _year,
	  date_part('month', dp.publication_date) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dp.sk_property) as _count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01'
		  and f.sk_property != -1
  group by date_part('year', dp.publication_date), date_part('month', dp.publication_date)
  order by date_part('year', dp.publication_date), date_part('month', dp.publication_date)
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
	from growth.new_listings_all_day d
	join growth.new_listings_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_month m
  	on d._year = m._year
    	and d._month = m._month
),
