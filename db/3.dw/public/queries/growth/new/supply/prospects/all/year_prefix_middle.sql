all_dates_last_year as (
	select
	 	date_part('year', f.dt_lead_and_prospect) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
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
  join partial_calc pc
  	on date_part('year', f.dt_lead_and_prospect) = date_part('year', add_months(current_date, -12))
  		and date_part('month', f.dt_lead_and_prospect) = date_part('month', add_months(current_date, -12))
  		and date_part('day', f.dt_lead_and_prospect) <= date_part('day', add_months(current_date, -12))
  group by date_part('year', f.dt_lead_and_prospect)
  order by date_part('year', f.dt_lead_and_prospect)
),
