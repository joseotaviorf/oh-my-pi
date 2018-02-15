with all_dates_prev as (
  select distinct
    date_part('year', f.dt_qualified) as _year,
    date_part('month', f.dt_qualified) as _month,
    date_part('week', f.dt_qualified) as _week,
    date_part('day', f.dt_qualified) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    row_number() over (partition by date_part('year', f.dt_qualified),
    																date_part('month', f.dt_qualified),
    																date_part('week', f.dt_qualified),
    																date_part('day', f.dt_qualified) order by f.dt_qualified asc)
    	+ row_number() over (partition by date_part('year', f.dt_qualified),
    																		date_part('month', f.dt_qualified),
    																		date_part('week', f.dt_qualified),
    																		date_part('day', f.dt_qualified) order by f.dt_qualified desc)
			- 1 as daily_count,
    row_number() over (partition by date_part('year', f.dt_qualified),
    																date_part('week', f.dt_qualified) order by f.dt_qualified asc)
    	+ row_number() over (partition by date_part('year', f.dt_qualified),
    																		date_part('week', f.dt_qualified) order by f.dt_qualified desc)
			- 1 as weekly_count,
    row_number() over (partition by date_part('year', f.dt_qualified),
    																date_part('month', f.dt_qualified) order by f.dt_qualified asc)
    	+ row_number() over (partition by date_part('year', f.dt_qualified),
    																		date_part('month', f.dt_qualified) order by f.dt_qualified desc)
			- 1 as monthly_count,
    row_number() over (partition by date_part('year', f.dt_qualified) order by f.dt_qualified asc)
    	+ row_number() over (partition by date_part('year', f.dt_qualified) order by f.dt_qualified desc)
			- 1 as yearly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_qualified >= '2017-01-01'
		  and f.cap_id != -1
  order by date_part('year', f.dt_qualified), date_part('month', f.dt_qualified), date_part('week', f.dt_qualified), date_part('day', f.dt_qualified)
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
	 	date_part('year', f.dt_qualified) as _year,
	  date_part('month', f.dt_qualified) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.dt_qualified) as monthly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_qualified >= '2017-01-01'
		  and f.cap_id != -1
  where date_part('year', f.dt_qualified) = date_part('year', add_months(current_date, -1))
  		and date_part('month', f.dt_qualified) = date_part('month', add_months(current_date, -1))
  		and date_part('day', f.dt_qualified) <= date_part('day', current_date)
  group by date_part('year', f.dt_qualified), date_part('month', f.dt_qualified)
  order by date_part('year', f.dt_qualified), date_part('month', f.dt_qualified)
),
all_dates_last_year as (
	select
	 	date_part('year', f.dt_qualified) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.dt_qualified) as yearly_count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cap
		on f.cap_id = cap.sk_cap_id
		  and f.dt_qualified >= '2017-01-01'
		  and f.cap_id != -1
  where date_part('year', f.dt_qualified) = date_part('year', add_months(current_date, -12))
  		and date_part('month', f.dt_qualified) = date_part('month', add_months(current_date, -12))
  		and date_part('day', f.dt_qualified) <= date_part('day', add_months(current_date, -12))
  group by date_part('year', f.dt_qualified)
  order by date_part('year', f.dt_qualified)
),