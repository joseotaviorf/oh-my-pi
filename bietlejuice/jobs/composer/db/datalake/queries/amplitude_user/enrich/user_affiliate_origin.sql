with amplitude_affiliate_tracking as(
	with amplitude_events as (
    SELECT
        id_user,
        coalesce(get_json_object(user_properties, '$.utm_source'), '') as utm_source,
        coalesce(get_json_object(user_properties, '$.utm_medium'), '') as utm_medium,
        coalesce(get_json_object(user_properties, '$.utm_campaign'), '') as utm_campaign,
        coalesce(get_json_object(user_properties, '$.utm_content'), '') as utm_content,
        coalesce(get_json_object(user_properties, '$.utm_term'), '') as utm_term,
        coalesce(get_json_object(user_properties, '$.platform'), '') as platform,
        coalesce(device_type, '') as device_type,
        coalesce(country, '') as country,
        coalesce(region, '') as region,
        coalesce(city, '') as city,
        ts_client_event,
        ts_event
    FROM datalake_amplitude_clean.events
    WHERE event_type IN ('signup_user_created', 'login_confirmation_viewed', 'home_page_viewed')
        AND id_app = 205027
        AND id_user is not null
    )
    select
      *,
      rank() over (partition by id_user order by ts_event, ts_client_event) as event_order
    from amplitude_events
)
select
	id_user,
	utm_source,
	utm_medium,
	utm_campaign,
	utm_content,
	utm_term,
	platform,
	device_type,
	country,
	region,
	city,
	ts_client_event
from
	amplitude_affiliate_tracking
where event_order = 1