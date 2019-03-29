with all_dates_prev as (
	select distinct
    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _year,
    date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _month,
    date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _week,
    date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _day,
    coalesce(dr.city_group, 'Not Mapped') as city_group,
    coalesce(dr.city_name, 'Not Mapped') as city,
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
    rank() over (partition by
                        coalesce(dr.city_name, ''),
                        date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
                        order by f.sk_lead asc)
    	+ rank() over (partition by
    	                coalesce(dr.city_name, ''),
    	                date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
                        order by f.sk_lead desc)
			- 1 as daily_count,
    rank() over (partition by
                        coalesce(dr.city_name, ''),
                        date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
                        order by f.sk_lead asc)
    	+ rank() over (partition by
    	                coalesce(dr.city_name, ''),
                        date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
                        order by f.sk_lead desc)
			- 1 as weekly_count,
    rank() over (partition by
                        coalesce(dr.city_name, ''),
                        date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
                        order by f.sk_lead asc)
    	+ rank() over (partition by
    	                coalesce(dr.city_name, ''),
                        date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
                        order by f.sk_lead desc)
			- 1 as monthly_count,
    rank() over (partition by
                        coalesce(dr.city_name, ''),
                        date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
                        f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
                        order by f.sk_lead asc)
    	+ rank() over (partition by
    	                coalesce(dr.city_name, ''),
                        date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    	                f.mkt_category,
                        f.mkt_flow,
                        f.mkt_completion,
                        f.mkt_channel,
                        f.mkt_medium,
                        f.mkt_source,
                        f.mkt_platform,
                        l.utm_campaign,
                        l.utm_content,
                        l.utm_term
    	                order by f.sk_lead desc)
			- 1 as yearly_count
	from fact_house_listing_flows f
	left join dim_region dr
		on f.sk_region = dr.sk_region
	join dim_lead l
        on f.sk_lead = l.sk_lead
	where f.sk_lead_date between 20180101 and to_char(current_date - 1, 'YYYYMMDD')::integer
  order by 6, 1, 2, 3, 4
),
all_dates as (
    select
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
        max(daily_count) as daily_count,
        max(weekly_count) as weekly_count,
        max(monthly_count) as monthly_count,
        max(yearly_count) as yearly_count
    from
        all_dates_prev
    group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
),