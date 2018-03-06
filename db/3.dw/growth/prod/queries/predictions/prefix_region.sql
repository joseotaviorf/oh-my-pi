with all_dates as (
  select
    date_part('year', cast(cast("date" as timestamp) as date))::int as _year,
    date_part('month', cast(cast("date" as timestamp) as date))::int as _month,
    date_part('week', cast(cast("date" as timestamp) as date))::int as _week,
    date_part('day', cast(cast("date" as timestamp) as date))::int as _day,
	  region,
    'QuintoAndar'::varchar as city,
    ({daily_count}::float)::int as daily_count,
    ({weekly_count}::float)::int as weekly_count,
    ({monthly_count}::float)::int as monthly_count,
    ({yearly_count}::float)::int as yearly_count
  from datalake_raw.growth_{funnel}_prediction
  where city != 'all'
    and region = 'all'
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	  date_part('year', cast(cast("date" as timestamp) as date))::int as _year,
    date_part('month', cast(cast("date" as timestamp) as date))::int as _month,
	  region,
	  'QuintoAndar'::varchar as city,
	  ({monthly_count}::float)::int as monthly_count
  from datalake_raw.growth_{funnel}_prediction
  where city = 'all'
    and region != 'all'
    and date_part('year', cast(cast("date" as timestamp) as date))::int = date_part('year', add_months(current_date, -1))
  	and date_part('month', cast(cast("date" as timestamp) as date))::int = date_part('month', add_months(current_date, -1))
  	and date_part('day', cast(cast("date" as timestamp) as date))::int < date_part('day', current_date)
  order by region, date_part('year', cast(cast("date" as timestamp) as date)), date_part('month', cast(cast("date" as timestamp) as date))
),
all_dates_last_year as (
	select
	 	date_part('year', cast(cast("date" as timestamp) as date))::int as _year,
	  region,
	  'QuintoAndar'::varchar as city,
  	({yearly_count}::float)::int as yearly_count
	from datalake_raw.growth_{funnel}_prediction
  where city = 'all'
    and region != 'all'
    and date_part('year', cast(cast("date" as timestamp) as date))::int = date_part('year', add_months(current_date, -12))
  	and ((date_part('month', cast(cast("date" as timestamp) as date))::int = date_part('month', add_months(current_date, -12))
  		     and date_part('day', cast(cast("date" as timestamp) as date))::int < date_part('day', add_months(current_date, -12)))
  		or date_part('month', cast(cast("date" as timestamp) as date))::int < date_part('month', add_months(current_date, -12))
    )
  order by region, date_part('year', cast(cast("date" as timestamp) as date))
),
