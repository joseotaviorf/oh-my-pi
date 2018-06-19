with all_dates_prev as (
  select distinct
    date_part('year', to_date(f.sk_prospect_date::varchar, 'YYYYMMDD')) as _year,
    date_part('month', to_date(f.sk_prospect_date::varchar, 'YYYYMMDD')) as _month,
    date_part('week', to_date(f.sk_prospect_date::varchar, 'YYYYMMDD')) as _week,
    date_part('day', to_date(f.sk_prospect_date::varchar, 'YYYYMMDD')) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    rank() over (partition by 1, 2, 3, 4 order by f.sk_lead asc)
    	+ rank() over (partition by 1, 2, 3, 4 order by f.sk_lead desc)
			- 1 as daily_count,
    rank() over (partition by 1, 3 order by f.sk_lead asc)
    	+ rank() over (partition by 1, 3 order by f.sk_lead desc)
			- 1 as weekly_count,
    rank() over (partition by 1, 2 order by f.sk_lead asc)
    	+ rank() over (partition by 1, 2 order by f.sk_lead desc)
			- 1 as monthly_count,
    rank() over (partition by 1 order by f.sk_lead asc)
    	+ rank() over (partition by 1 order by f.sk_lead desc)
			- 1 as yearly_count
	from fact_supply f
	where f.sk_prospect_date between 20170101 and to_date(current_date - 1, 'YYYYMMDD')::integer
  order by 1, 2, 3, 4
),
all_dates as (
  select distinct
    _year,
    _month,
    _week,
    _day,
    region,
    city,
    max(daily_count) over (partition by _year, _month, _week, _day) as daily_count,
    max(weekly_count) over (partition by _year, _week) as weekly_count,
    max(monthly_count) over (partition by _year, _month) as monthly_count,
    max(yearly_count) over (partition by _year) as yearly_count
  from all_dates_prev
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	  substring(f.sk_prospect_date::varchar, 0, 5) as _year,
	  substring(f.sk_prospect_date::varchar, 5, 2) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.sk_prospect_date) as monthly_count
	from fact_supply f
	where f.sk_prospect_date between to_char(add_months(date_trunc('month', current_date), -1), 'YYYYMMDD')::integer
    and to_char(add_months(current_date - 1, -1), 'YYYYMMDD')::integer
  group by 1, 2
  order by 1, 2
),
all_dates_last_year as (
	select
	 	substring(f.sk_prospect_date::varchar, 0, 5) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(f.sk_prospect_date) as yearly_count
	from fact_supply f
	where f.sk_prospect_date between to_char(add_months(date_trunc('year', current_date), -12), 'YYYYMMDD')::integer
    and to_char(add_months(current_date - 1, -12), 'YYYYMMDD')::integer
  group by 1
  order by 1
),