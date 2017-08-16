select
	app,
	'iOS' as app_type,
	event_time,
	regexp_extract(
	    coalesce(
		regexp_replace(event_properties.visita_id, '\[|\]', ''),
		event_properties.visita_code,
		regexp_extract(event_properties.uri,'\w+$')
		), '^[0-9A-F]+$') as visita_id,
	user_properties.adjust_network as media_source,
	user_properties.adjust_network,
	user_properties.utm_source,
	user_properties.utm_campaign,
	user_properties.utm_medium
from
	amplitude.ev_ios_booking_media_sources
union
select
	app,
	'Android' as app_type,
	event_time,
	regexp_extract(
	    coalesce(
		regexp_replace(event_properties.visita_id, '\[|\]', ''),
		event_properties.visita_code,
		regexp_extract(event_properties.uri,'\w+$')
		), '^[0-9A-F]+$') as visita_id,
	user_properties.adjust_network as media_source,
	user_properties.adjust_network,
	user_properties.utm_source,
	user_properties.utm_campaign,
	user_properties.utm_medium
from
	amplitude.ev_android_booking_media_sources
union
select
	app,
	'Web' as app_type,
	event_time,
	regexp_extract(
	    coalesce(
		regexp_replace(event_properties.visita_id, '\[|\]', ''),
		event_properties.visita_code,
		regexp_extract(event_properties.uri,'\w+$')
		), '^[0-9A-F]+$') as visita_id,
	coalesce(user_properties.utm_source,'organic') as media_source,
	user_properties.adjust_network,
	coalesce(user_properties.utm_source,'organic') as utm_source,
	user_properties.utm_campaign,
	user_properties.utm_medium
from
	amplitude.ev_web_booking_media_sources