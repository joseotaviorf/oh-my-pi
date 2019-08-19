with all_dates as (
  select distinct
    date_part('year', db.dt_created) as _year,
    date_part('month', db.dt_created) as _month,
    date_part('week', db.dt_created) as _week,
    date_part('day', db.dt_created) as _day,
    coalesce(dr.city_group, 'Not Mapped') as city_group,
    coalesce(dr.city_name, 'Not Mapped') as city,
    drft.mkt_category,
	drft.mkt_flow,
	drft.mkt_completion,
	'Not Mapped' as mkt_origin,
	drft.mkt_channel,
	drft.mkt_medium,
	drft.mkt_source,
	drft.mkt_platform,
	f.booking_utm_campaign as utm_campaign,
	f.booking_utm_content as utm_content,
	f.booking_utm_term as utm_term,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created),
                                    date_part('month', db.dt_created),
                                    date_part('week', db.dt_created),
                                    date_part('day', db.dt_created),
                                    drft.mkt_category,
                                    drft.mkt_flow,
                                    drft.mkt_completion,
                                    drft.mkt_channel,
                                    drft.mkt_medium,
                                    drft.mkt_source,
                                    drft.mkt_platform,
                                    f.booking_utm_campaign,
                                    f.booking_utm_content,
                                    f.booking_utm_term
                                    order by dc.sk_contract asc)
    	+ dense_rank() over (partition by   coalesce(dr.city_name, ''),
                                            date_part('year', db.dt_created),
                                            date_part('month', db.dt_created),
                                            date_part('week', db.dt_created),
                                            date_part('day', db.dt_created),
                                            drft.mkt_category,
                                            drft.mkt_flow,
                                            drft.mkt_completion,
                                            drft.mkt_channel,
                                            drft.mkt_medium,
                                            drft.mkt_source,
                                            drft.mkt_platform,
                                            f.booking_utm_campaign,
                                            f.booking_utm_content,
                                            f.booking_utm_term
                                            order by dc.sk_contract desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created),
                                    date_part('week', db.dt_created),
                                    drft.mkt_category,
                                    drft.mkt_flow,
                                    drft.mkt_completion,
                                    drft.mkt_channel,
                                    drft.mkt_medium,
                                    drft.mkt_source,
                                    drft.mkt_platform,
                                    f.booking_utm_campaign,
                                    f.booking_utm_content,
                                    f.booking_utm_term
                                    order by dc.sk_contract asc)
    	+ dense_rank() over (partition by   coalesce(dr.city_name, ''),
                                            date_part('year', db.dt_created),
                                            date_part('week', db.dt_created),
                                            drft.mkt_category,
                                            drft.mkt_flow,
                                            drft.mkt_completion,
                                            drft.mkt_channel,
                                            drft.mkt_medium,
                                            drft.mkt_source,
                                            drft.mkt_platform,
                                            f.booking_utm_campaign,
                                            f.booking_utm_content,
                                            f.booking_utm_term
                                            order by dc.sk_contract desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created),
                                    date_part('month', db.dt_created),
                                    drft.mkt_category,
                                    drft.mkt_flow,
                                    drft.mkt_completion,
                                    drft.mkt_channel,
                                    drft.mkt_medium,
                                    drft.mkt_source,
                                    drft.mkt_platform,
                                    f.booking_utm_campaign,
                                    f.booking_utm_content,
                                    f.booking_utm_term
                                    order by dc.sk_contract asc)
    	+ dense_rank() over (partition by   coalesce(dr.city_name, ''),
                                            date_part('year', db.dt_created),
                                            date_part('month', db.dt_created),
                                            drft.mkt_category,
                                            drft.mkt_flow,
                                            drft.mkt_completion,
                                            drft.mkt_channel,
                                            drft.mkt_medium,
                                            drft.mkt_source,
                                            drft.mkt_platform,
                                            f.booking_utm_campaign,
                                            f.booking_utm_content,
                                            f.booking_utm_term
                                            order by dc.sk_contract desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', db.dt_created),
                                    drft.mkt_category,
                                    drft.mkt_flow,
                                    drft.mkt_completion,
                                    drft.mkt_channel,
                                    drft.mkt_medium,
                                    drft.mkt_source,
                                    drft.mkt_platform,
                                    f.booking_utm_campaign,
                                    f.booking_utm_content,
                                    f.booking_utm_term
                                    order by dc.sk_contract asc)
    	+ dense_rank() over (partition by   coalesce(dr.city_name, ''),
                                            date_part('year', db.dt_created),
                                            drft.mkt_category,
                                            drft.mkt_flow,
                                            drft.mkt_completion,
                                            drft.mkt_channel,
                                            drft.mkt_medium,
                                            drft.mkt_source,
                                            drft.mkt_platform,
                                            f.booking_utm_campaign,
                                            f.booking_utm_content,
                                            f.booking_utm_term
                                            order by dc.sk_contract desc)
			- 1 as yearly_count
	from fact_listing_rent_flows f
	join dim_booking db
		on f.sk_booking = db.sk_booking
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
		and f.sk_contract_signed_date > 0
	left join dim_rent_flow_taxonomy drft
	    on f.sk_rent_flow_taxonomy = drft.sk_rent_flow_taxonomy
    left join dim_region dr
  	    on f.sk_region = dr.sk_region
  order by 1, 2, 3, 4
),