all_dates_last_month as (
	select
    date_part('year', f.dt_opportunity) as _year,
    date_part('month', f.dt_opportunity) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
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
	join partial_calc pc
  	on date_part('year', f.dt_opportunity) = date_part('year', add_months(current_date, -1))
  		and date_part('month', f.dt_opportunity) = date_part('month', add_months(current_date, -1))
  		and date_part('day', f.dt_opportunity) <= date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity), date_part('month', f.dt_opportunity)
  order by coalesce(dr.city_name, ''), date_part('year', f.dt_opportunity), date_part('month', f.dt_opportunity)
),