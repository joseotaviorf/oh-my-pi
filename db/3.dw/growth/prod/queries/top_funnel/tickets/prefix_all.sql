with all_dates as (
  select distinct
    date_part('year', b.dt_created) as _year,
    date_part('month', b.dt_created) as _month,
    date_part('week', b.dt_created) as _week,
    date_part('day', b.dt_created) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    _count as daily_count,
    sum(_count) over (partition by date_part('year', b.dt_created),
                                    date_part('week', b.dt_created)) as weekly_count,
    sum(_count) over (partition by date_part('year', b.dt_created),
                                    date_part('month', b.dt_created)) as monthly_count,
    sum(_count) over (partition by date_part('year', b.dt_created)) as yearly_count
  from growth_staging.post_contract_ticket_base b
  order by date_part('year', b.dt_created), date_part('month', b.dt_created), date_part('week', b.dt_created), date_part('day', b.dt_created)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	 	date_part('year', b.dt_created) as _year,
	  date_part('month', b.dt_created) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	sum(_count) as monthly_count
	from growth_staging.post_contract_ticket_base b
  where date_part('year', b.dt_created) = date_part('year', add_months(current_date, -1))
  		and date_part('month', b.dt_created) = date_part('month', add_months(current_date, -1))
  		and date_part('day', b.dt_created) <= date_part('day', current_date)
  group by date_part('year', b.dt_created), date_part('month', b.dt_created)
  order by date_part('year', b.dt_created), date_part('month', b.dt_created)
),
all_dates_last_year as (
	select
	 	date_part('year', b.dt_created) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	sum(_count) as yearly_count
	from growth_staging.post_contract_ticket_base b
  where date_part('year', b.dt_created) = date_part('year', add_months(current_date, -12))
  		and date_part('month', b.dt_created) = date_part('month', add_months(current_date, -12))
  		and date_part('day', b.dt_created) <= date_part('day', add_months(current_date, -12))
  group by date_part('year', b.dt_created)
  order by date_part('year', b.dt_created)
),