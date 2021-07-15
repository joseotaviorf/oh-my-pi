SELECT
	et.id_user_dispatch,
	et.id_user_braze,
	et.event_channel,
	send_tenants.ts_event AS ts_push_sent,
	open_tenants.ts_event AS ts_push_opened,
	bounce_tenants.ts_event AS ts_push_bounced,
	et.year,
	et.month,
	et.day
FROM
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants AS send_tenants
		ON et.id_user_dispatch = send_tenants.id_user_dispatch
		AND send_tenants.event_type = 'users.messages.pushnotification.Send'
LEFT JOIN
	datalake_braze.events_tenants AS open_tenants
		ON et.id_user_dispatch = open_tenants.id_user_dispatch
		AND open_tenants.event_type = 'users.messages.pushnotification.Open'
LEFT JOIN
	datalake_braze.events_tenants AS bounce_tenants
		ON et.id_user_dispatch = bounce_tenants.id_user_dispatch
		AND bounce_tenants.event_type = 'users.messages.pushnotification.Bounce'
WHERE
	et.event_channel = 'pushnotification'
	AND et.year = {year}
	AND et.month = {month}
	AND et.day = {day}
GROUP BY
	1,2,3,4,5,6,7,8,9
