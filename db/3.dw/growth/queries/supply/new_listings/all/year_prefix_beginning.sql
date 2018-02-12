with all_dates_all_year as (
	select
		date_part('year', dp.publication_date) as _year,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct dp.sk_property) as _count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01'
		  and f.sk_property != -1
	group by date_part('year', dp.publication_date)
	order by date_part('year', dp.publication_date)
),
all_dates as (
	select distinct
    d._year,
    d._month,
    w._week,
    d._day,
    d.region,
    d.city,
    y._count as yearly_count
	from growth.new_listings_all_day d
	join growth.new_listings_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_year y
  	on d._year = y._year
),
