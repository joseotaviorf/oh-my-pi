with all_dates as (
  select
    date_part('year', f.dt_contact) as _year,
    date_part('month', f.dt_contact) as _month,
    date_part('week', f.dt_contact) as _week,
    date_part('day', f.dt_contact) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    count(f.dt_contact) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_contact >= '2017-01-01'
		  and f.cap_id != -1
  group by date_part('year', f.dt_contact), date_part('month', f.dt_contact), date_part('week', f.dt_contact), date_part('day', f.dt_contact)
  order by date_part('year', f.dt_contact), date_part('month', f.dt_contact), date_part('week', f.dt_contact), date_part('day', f.dt_contact)
),
