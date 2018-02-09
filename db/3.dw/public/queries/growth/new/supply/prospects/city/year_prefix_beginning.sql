with all_dates_city_year as (
	select
		date_part('year', f.dt_lead_and_prospect) as _year,
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
	group by coalesce(dr.city_name, ''), date_part('year', f.dt_lead_and_prospect)
	order by coalesce(dr.city_name, ''), date_part('year', f.dt_lead_and_prospect)
),
all_dates as (
	select distinct
    y._year,
    d._month,
    w._week,
    d._day,
    y.region,
    y.city,
    y._count as yearly_count
	from growth.prospects_city_day d
	join growth.prospects_city_week w
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_city_year y
  	on d.city = y.city
  		and d.region = y.region
  		and d._year = y._year
),
