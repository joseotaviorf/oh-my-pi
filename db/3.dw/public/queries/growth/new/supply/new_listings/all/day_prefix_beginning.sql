with all_dates as (
  select
    date_part('year', dp.publication_date) as _year,
    date_part('month', dp.publication_date) as _month,
    date_part('week', dp.publication_date) as _week,
    date_part('day', dp.publication_date) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    count(distinct dp.sk_property) as _count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01'
		  and f.sk_property != -1
  group by date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date), date_part('day', dp.publication_date)
  order by date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date), date_part('day', dp.publication_date)
),
