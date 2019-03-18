year_calc_prev as (
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
        mkt_channel,
        mkt_medium,
        mkt_source,
        mkt_platform,
        utm_campaign,
        utm_content,
        utm_term,
		ad.yearly_count
	from all_dates ad
),
result as (
	select
		(mycp._year::varchar || lpad(mycp._month::varchar, 2 , '0') || lpad(mycp._day::varchar, 2, '0'))::integer as sk_date,
		case
			when mycp._week = 1
				then to_date(mycp._year::varchar || '0101', 'YYYYMMDD')
			else dateadd(week, mycp._week::integer - 1, to_date(mycp._year::varchar || '0101', 'YYYYMMDD'))::date
		end as sk_week_start_date,
		mycp._year,
		mycp._month,
		mycp._week,
		mycp._day,
		mycp.city_group,
		mycp.city,
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
		0 as daily_count,
		0 as weekly_count,
		0 as monthly_count,
		mycp.yearly_count
	from year_calc_prev mycp
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
