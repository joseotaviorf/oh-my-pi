with amplitude_affiliate_tracking as(
	with amplitude as (
    SELECT DISTINCT
        id_user as user_id,
        coalesce(cast(json_extract(user_properties, '$.utm_source') as varchar), '') as u_utm_source,
        coalesce(cast(json_extract(user_properties, '$.utm_medium') as varchar), '') as u_utm_medium,
        coalesce(cast(json_extract(user_properties, '$.utm_campaign') as varchar), '') as u_utm_campaign,
        coalesce(cast(json_extract(user_properties, '$.utm_content') as varchar), '') as u_utm_content,
        coalesce(cast(json_extract(user_properties, '$.utm_term') as varchar), '') as u_utm_term,
        coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as u_platform,
        coalesce(device_type, '') as device_type,
        coalesce(country, '') as country,
        coalesce(region, '') as region,
        coalesce(city, '') as city,
        ts_client_event as client_event_time,
        ts_event
    FROM datalake_amplitude_clean_prod.events
    WHERE event_type IN ('signup_user_created', 'login_confirmation_viewed', 'home_page_viewed')
        AND id_app = 205027
        AND id_user is not null
    )
    select
      *,
      rank() over (partition by user_id order by ts_event, client_event_time) as event_order
    from amplitude
)
select
	user_id,
	u_utm_source,
	u_utm_medium,
	u_utm_campaign,
	u_utm_content,
	u_utm_term,
	u_platform,
	device_type,
	country,
	region,
	city,
	client_event_time
from
	amplitude_affiliate_tracking
where event_order = 1