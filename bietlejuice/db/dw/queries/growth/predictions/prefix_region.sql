with all_dates as (
  select distinct
    date_part('year', cast(cast("date" as timestamp) as date))::int as _year,
    date_part('month', cast(cast("date" as timestamp) as date))::int as _month,
    date_part('week', cast(cast("date" as timestamp) as date))::int as _week,
    date_part('day', cast(cast("date" as timestamp) as date))::int as _day,
	  region_code as region,
    'QuintoAndar'::varchar as city,
    ({daily_count}::float)::int as daily_count,
    max({weekly_count}::float::int) over (partition by date_part('year', cast(cast("date" as timestamp) as date)), date_part('week', cast(cast("date" as timestamp) as date))) as weekly_count,
    max({monthly_count}::float::int) over (partition by date_part('year', cast(cast("date" as timestamp) as date)), date_part('month', cast(cast("date" as timestamp) as date))) as monthly_count,
    max({yearly_count}::float::int) over (partition by date_part('year', cast(cast("date" as timestamp) as date))) as yearly_count
  from datalake_raw.growth_{funnel}_prediction
  where city = 'all'
    and region != 'all'
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select distinct
	  date_part('year', cast(cast("date" as timestamp) as date))::int as _year,
    date_part('month', cast(cast("date" as timestamp) as date))::int as _month,
	  region_code as region,
	  'QuintoAndar'::varchar as city,
	  max({monthly_count}::float::int) over (partition by date_part('year', cast(cast("date" as timestamp) as date)), date_part('month', cast(cast("date" as timestamp) as date))) as monthly_count
  from datalake_raw.growth_{funnel}_prediction
  where city = 'all'
    and region != 'all'
    and date_part('year', cast(cast("date" as timestamp) as date))::int = date_part('year', add_months(current_date, -1))
  	and date_part('month', cast(cast("date" as timestamp) as date))::int = date_part('month', add_months(current_date, -1))
  	and date_part('day', cast(cast("date" as timestamp) as date))::int < date_part('day', current_date)
  order by 3, 1, 2
),
all_dates_last_year as (
	select distinct
	 	date_part('year', cast(cast("date" as timestamp) as date))::int as _year,
	  region_code as region,
	  'QuintoAndar'::varchar as city,
  	max({yearly_count}::float::int) over (partition by date_part('year', cast(cast("date" as timestamp) as date))) as yearly_count
	from datalake_raw.growth_{funnel}_prediction
  where city = 'all'
    and region != 'all'
    and date_part('year', cast(cast("date" as timestamp) as date))::int = date_part('year', add_months(current_date, -12))
  	and ((date_part('month', cast(cast("date" as timestamp) as date))::int = date_part('month', add_months(current_date, -12))
  		     and date_part('day', cast(cast("date" as timestamp) as date))::int < date_part('day', add_months(current_date, -12)))
  		or date_part('month', cast(cast("date" as timestamp) as date))::int < date_part('month', add_months(current_date, -12))
    )
  order by 2, 1
),
