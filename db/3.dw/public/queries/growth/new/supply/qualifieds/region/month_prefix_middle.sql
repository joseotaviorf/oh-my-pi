all_dates_last_month as (
	select
    date_part('year', f.dt_qualified) as _year,
    date_part('month', f.dt_qualified) as _month,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(f.dt_qualified) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_qualified >= '2017-01-01'
		  and f.cap_id != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	join partial_calc pc
  	on date_part('year', f.dt_qualified) = date_part('year', add_months(current_date, -1))
  		and date_part('month', f.dt_qualified) = date_part('month', add_months(current_date, -1))
  		and date_part('day', f.dt_qualified) <= date_part('day', current_date)
 	group by coalesce(dr.long_region_name, ''), date_part('year', f.dt_qualified), date_part('month', f.dt_qualified)
  order by coalesce(dr.long_region_name, ''), date_part('year', f.dt_qualified), date_part('month', f.dt_qualified)
),
