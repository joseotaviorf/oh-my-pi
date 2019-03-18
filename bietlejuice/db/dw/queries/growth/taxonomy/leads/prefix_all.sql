with all_dates_prev as (
  select distinct
    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _year,
    date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _month,
    date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _week,
    date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _day,
    'QuintoAndar'::varchar as city_group,
    'QuintoAndar'::varchar as city,
    f.mkt_category,
	f.mkt_flow,
	f.mkt_completion,
	f.mkt_channel,
	f.mkt_medium,
	f.mkt_source,
	f.mkt_platform,
	l.utm_campaign,
	l.utm_content,
	l.utm_term,
    rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                              date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                              date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                              date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    	                            date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    	                            date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    	                            date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as daily_count,
    rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                              date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    	                            date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as weekly_count,
    rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                              date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    	                            date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as monthly_count,
    rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as yearly_count
	from fact_house_listing_flows f
	join dim_lead l
        on f.sk_lead = l.sk_lead
	where f.sk_lead_date between 20180101 and to_char(current_date - 1, 'YYYYMMDD')::integer
  order by 1, 2, 3, 4
),
all_dates as (
  select distinct
    _year,
    _month,
    _week,
    _day,
    city_group,
    city,
    mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_channel,
	mkt_medium,
	mkt_source,
	mkt_platform,
	utm_campaign,
	utm_content,
	utm_term,
    max(daily_count) over (partition by _year, _month, _week, _day) as daily_count,
    max(weekly_count) over (partition by _year, _week) as weekly_count,
    max(monthly_count) over (partition by _year, _month) as monthly_count,
    max(yearly_count) over (partition by _year) as yearly_count
  from all_dates_prev
),