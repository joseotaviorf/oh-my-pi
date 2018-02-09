all_dates_last_month as (
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
  join partial_calc pc
  	on date_part('year', dp.publication_date) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dp.publication_date) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dp.publication_date) <= date_part('day', current_date)
  group by date_part('year', dp.publication_date), date_part('month', dp.publication_date)
  order by date_part('year', dp.publication_date), date_part('month', dp.publication_date)
),
