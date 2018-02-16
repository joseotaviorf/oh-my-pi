with all_dates as (
	select distinct
		_year,
		_month,
		_week,
		_day,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		daily_avg as daily_count,
		weekly_avg as weekly_count,
		monthly_avg as monthly_count,
		yearly_avg as yearly_count
  from growth_staging.post_contract_ticket_full_resolution_time
	order by _year, _month, _week, _day
),
all_dates_last_month as (
	select
		_year,
		_month,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		last_monthly_avg as monthly_count
  from growth_staging.post_contract_ticket_full_resolution_time
	order by _year, _month
),
all_dates_last_year as (
	select
		_year,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		last_yearly_avg as yearly_count
  from growth_staging.post_contract_ticket_full_resolution_time
	order by _year
),