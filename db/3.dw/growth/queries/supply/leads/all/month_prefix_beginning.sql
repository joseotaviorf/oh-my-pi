with all_dates_all_month as (
	select
	 	date_part('year', f.dt_contact) as _year,
	  date_part('month', f.dt_contact) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.dt_contact) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_contact >= '2017-01-01'
		  and f.cap_id != -1
  group by date_part('year', f.dt_contact), date_part('month', f.dt_contact)
  order by date_part('year', f.dt_contact), date_part('month', f.dt_contact)
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
	from growth.leads_all_day d
	join growth.leads_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_month m
  	on d._year = m._year
    	and d._month = m._month
),
