with all_dates as (
	select distinct
    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _year,
    date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _month,
    date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _week,
    date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _day,
    coalesce(dr.city_group, 'Not Mapped')  as city_group,
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
                        order by f.sk_house_listing asc)
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
                        order by f.sk_house_listing desc)
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
                        order by f.sk_house_listing asc)
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
                        order by f.sk_house_listing desc)
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
                        order by f.sk_house_listing asc)
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
                        order by f.sk_house_listing desc)
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
                        order by f.sk_house_listing asc)
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
    	                order by f.sk_house_listing desc)
			- 1 as yearly_count
	from fact_house_listing_flows f
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house_listing
	left join dim_region dr
		on fhl.sk_region = dr.sk_region
	left join dim_lead l
        on f.sk_lead = l.sk_lead
	where f.sk_first_listing_date between 20180101 and to_char(current_date - 1, 'YYYYMMDD')::integer
  order by 6, 1, 2, 3, 4
),