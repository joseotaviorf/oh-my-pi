with all_dates as (
  select
    _year,
    _month,
    _week,
    _day,
    region,
    city,
    daily_count,
    weekly_count,
    monthly_count,
    yearly_count
  from growth.amplitude_engaged_users
  where city = 'QuintoAndar'
    and (region is null or region != 'QuintoAndar')
    and partial is false
),
all_dates_last_week as (
	select distinct
	  _year,
	  _month,
	  _week,
	  region,
	  city,
	  weekly_count
	from growth.amplitude_engaged_users
  where city = 'QuintoAndar'
    and (region is null or region != 'QuintoAndar')
    and partial is true
),
all_dates_last_month as (
	select distinct
	  _year,
	  _month,
	  region,
	  city,
	  monthly_count
	from growth.amplitude_engaged_users
  where city = 'QuintoAndar'
    and (region is null or region != 'QuintoAndar')
    and partial is true
),
all_dates_last_year as (
	select distinct
	  _year,
	  region,
	  city,
	  yearly_count
	from growth.amplitude_engaged_users
  where city = 'QuintoAndar'
    and (region is null or region != 'QuintoAndar')
    and partial is true
),
