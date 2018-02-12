all_dates_last_month as (
	select
    date_part('year', f.dt_lead_and_prospect) as _year,
    date_part('month', f.dt_lead_and_prospect) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(f.dt_lead_and_prospect) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cp
	  on f.cap_id = cp.sk_cap_id
			and ((cp.status != 'Descartado'
	  		and cp.automatically_discarded is not true
	  		and cp.self_service is false)
	  	or cp.self_service is true)
	  	and f.dt_lead_and_prospect >= '2017-01-01'
	  	and f.cap_id != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	join partial_calc pc
  	on date_part('year', f.dt_lead_and_prospect) = date_part('year', add_months(current_date, -1))
  		and date_part('month', f.dt_lead_and_prospect) = date_part('month', add_months(current_date, -1))
  		and date_part('day', f.dt_lead_and_prospect) <= date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect)
  order by coalesce(dr.city_name, ''), date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect)
),