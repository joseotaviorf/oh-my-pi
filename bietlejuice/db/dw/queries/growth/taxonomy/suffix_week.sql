partial_calc_prev as (
	select
		ad._year,
		ad._month,
		ad._week,
		ad._day,
		ad.city_group,
		ad.city,
        mkt_category,
        mkt_flow,
        mkt_completion,
	    mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        mkt_platform,
        utm_campaign,
        utm_content,
        utm_term,
		ad.weekly_count
	from all_dates ad
),
result as (
	select
		(_year::varchar || lpad(_month::varchar, 2 , '0') || lpad(_day::varchar, 2, '0'))::integer as sk_date,
		case
			when _week = 1
				then to_date(_year::varchar || '0101', 'YYYYMMDD')
			else dateadd(week, _week::integer - 1, to_date(_year::varchar || '0101', 'YYYYMMDD'))::date
		end as sk_week_start_date,
		_year,
		_month,
		_week,
		_day,
		city_group,
		city,
		mkt_category,
        mkt_flow,
        mkt_completion,
	    mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        mkt_platform,
        utm_campaign,
        utm_content,
        utm_term,
		0 as daily_count,
		weekly_count,
		0 as monthly_count,
		0 as yearly_count
	from partial_calc_prev
)
select
  sk_date,
	(date_part('year', sk_week_start_date)::varchar
		|| lpad(date_part('month', sk_week_start_date)::varchar, 2, '0')
		|| lpad(date_part('day', sk_week_start_date)::varchar, 2, '0'))::integer as sk_week_start_date,
	_year::int,
	_month::int,
	_week::int,
	_day::int,
	city_group,
	city,
	mkt_category,
    mkt_flow,
    mkt_completion,
	mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_platform,
    utm_campaign,
    utm_content,
    utm_term,
	daily_count,
	weekly_count,
	monthly_count,
	yearly_count
from result
;