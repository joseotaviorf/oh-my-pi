all_dates_last_year as (
	select
	 	date_part('year', f.dt_qualified) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.dt_qualified) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_qualified >= '2017-01-01'
		  and f.cap_id != -1
  join partial_calc pc
  	on date_part('year', f.dt_qualified) = date_part('year', add_months(current_date, -12))
  		and date_part('month', f.dt_qualified) = date_part('month', add_months(current_date, -12))
  		and date_part('day', f.dt_qualified) <= date_part('day', add_months(current_date, -12))
  group by date_part('year', f.dt_qualified)
  order by date_part('year', f.dt_qualified)
),
