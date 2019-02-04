with amplitude_affiliate_tracking as(
select
	user_id,
	u_utm_source,
	u_utm_medium,
	u_platform,
	device_type,
	country,
	region,
	city,
	client_event_time,
	rank() over (partition by user_id order by event_time, client_event_time) as event_order
from datalake_clean.amplitude_events
where et in ('login_confirmation_viewed', 'home_page_viewed')
and app='205027'
and user_id <> ''
)
select
	user_id,
	u_utm_source,
	u_utm_medium,
	u_platform,
	device_type,
	country,
	region,
	city,
	case
		when
			length(client_event_time) > 19 then date_parse(client_event_time, '%Y-%m-%d %H:%i:%s.%f')
		else date_parse(client_event_time, '%Y-%m-%d %H:%i:%s') end
		as client_event_time
from
	amplitude_affiliate_tracking
where event_order = 1