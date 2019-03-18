with all_dates as (
	select distinct
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
    date_part('week', db.dt_created) as _week,
    date_part('day', db.dt_created) as _day,
    coalesce(dr.city_group, '') as city_group,
    'QuintoAndar'::varchar as city,
    db.mkt_category,
	db.mkt_flow,
	db.mkt_completion,
	db.mkt_channel,
	db.mkt_medium,
	db.mkt_source,
	db.mkt_platform,
	db.utm_campaign,
	db.utm_content,
	db.utm_term,
    dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    date_part('month', db.dt_created),
                                    date_part('week', db.dt_created),
                                    date_part('day', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    date_part('month', db.dt_created),
                                    date_part('week', db.dt_created),
                                    date_part('day', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    date_part('week', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    date_part('week', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    date_part('month', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    date_part('month', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking asc)
    	+ dense_rank() over (partition by coalesce(dr.city_group, ''),
                                    date_part('year', db.dt_created),
                                    db.mkt_category,
                                    db.mkt_flow,
                                    db.mkt_completion,
                                    db.mkt_channel,
                                    db.mkt_medium,
                                    db.mkt_source,
                                    db.mkt_platform,
                                    db.utm_campaign,
                                    db.utm_content,
                                    db.utm_term
                                    order by db.id_booking desc)
			- 1 as yearly_count
	from fact_listing_rent_flows f
	join dim_booking db
		on f.sk_booking = db.sk_booking
			and db.dt_created >= '2018-01-01' and db.dt_created < current_date
			and f.sk_booking != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = f.sk_house_listing
    left join dim_region dr
  	  on fhl.sk_region = dr.sk_region
  order by coalesce(dr.city_group, ''), date_part('year', db.dt_created), date_part('month', db.dt_created), date_part('week', db.dt_created), date_part('day', db.dt_created)
),