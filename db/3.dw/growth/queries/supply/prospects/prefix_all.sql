with all_dates_prev as (
  select distinct
    date_part('year', f.dt_lead_and_prospect) as _year,
    date_part('month', f.dt_lead_and_prospect) as _month,
    date_part('week', f.dt_lead_and_prospect) as _week,
    date_part('day', f.dt_lead_and_prospect) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    row_number() over (partition by date_part('year', f.dt_lead_and_prospect),
    																date_part('month', f.dt_lead_and_prospect),
    																date_part('week', f.dt_lead_and_prospect),
    																date_part('day', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect asc)
    	+ row_number() over (partition by date_part('year', f.dt_lead_and_prospect),
    																		date_part('month', f.dt_lead_and_prospect),
    																		date_part('week', f.dt_lead_and_prospect),
    																		date_part('day', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect desc)
			- 1 as daily_count,
    row_number() over (partition by date_part('year', f.dt_lead_and_prospect),
    																date_part('week', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect asc)
    	+ row_number() over (partition by date_part('year', f.dt_lead_and_prospect),
    																		date_part('week', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect desc)
			- 1 as weekly_count,
    row_number() over (partition by date_part('year', f.dt_lead_and_prospect),
    																date_part('month', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect asc)
    	+ row_number() over (partition by date_part('year', f.dt_lead_and_prospect),
    																		date_part('month', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect desc)
			- 1 as monthly_count,
    row_number() over (partition by date_part('year', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect asc)
    	+ row_number() over (partition by date_part('year', f.dt_lead_and_prospect) order by f.dt_lead_and_prospect desc)
			- 1 as yearly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cp
	  on f.cap_id = cp.sk_cap_id
				and ((not(cp.status = 'Descartado'
	  		and cp.automatically_discarded is true)
	  		and cp.self_service is false)
	  	or cp.self_service is true)
	  	and f.dt_lead_and_prospect >= '2017-01-01'
	  	and f.cap_id != -1
  order by date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect), date_part('week', f.dt_lead_and_prospect), date_part('day', f.dt_lead_and_prospect)
),
all_dates as (
  select distinct
    _year,
    _month,
    _week,
    _day,
    region,
    city,
    max(daily_count) over (partition by _day) as daily_count,
    max(weekly_count) over (partition by _week) as weekly_count,
    max(monthly_count) over (partition by _month) as monthly_count,
    max(yearly_count) over (partition by _year) as yearly_count
  from all_dates_prev
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	 	date_part('year', f.dt_lead_and_prospect) as _year,
	  date_part('month', f.dt_lead_and_prospect) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.dt_lead_and_prospect) as monthly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cp
	  on f.cap_id = cp.sk_cap_id
			and ((not(cp.status = 'Descartado'
	  		and cp.automatically_discarded is true)
	  		and cp.self_service is false)
	  	or cp.self_service is true)
	  	and f.dt_lead_and_prospect >= '2017-01-01'
	  	and f.cap_id != -1
  where date_part('year', f.dt_lead_and_prospect) = date_part('year', add_months(current_date, -1))
  		and date_part('month', f.dt_lead_and_prospect) = date_part('month', add_months(current_date, -1))
  		and date_part('day', f.dt_lead_and_prospect) <= date_part('day', current_date)
  group by date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect)
  order by date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect)
),
all_dates_last_year as (
	select
	 	date_part('year', f.dt_lead_and_prospect) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.dt_lead_and_prospect) as yearly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cp
	  on f.cap_id = cp.sk_cap_id
			and ((not(cp.status = 'Descartado'
	  		and cp.automatically_discarded is true)
	  		and cp.self_service is false)
	  	or cp.self_service is true)
	  	and f.dt_lead_and_prospect >= '2017-01-01'
	  	and f.cap_id != -1
  where date_part('year', f.dt_lead_and_prospect) = date_part('year', add_months(current_date, -12))
  		and date_part('month', f.dt_lead_and_prospect) = date_part('month', add_months(current_date, -12))
  		and date_part('day', f.dt_lead_and_prospect) <= date_part('day', add_months(current_date, -12))
  group by date_part('year', f.dt_lead_and_prospect)
  order by date_part('year', f.dt_lead_and_prospect)
),