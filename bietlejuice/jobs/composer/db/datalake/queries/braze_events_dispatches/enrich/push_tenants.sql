SELECT
	et.id_dispatch,
	et.id_user_braze,
	send_tenants.ts_event AS ts_push_sent,
	open_tenants.ts_event AS ts_push_opened,
	bounce_tenants.ts_event AS ts_push_bounced
FROM
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants AS send_tenants
		ON et.id_dispatch = send_tenants.id_dispatch
		AND et.id_braze = send_tenants.id_braze
		AND send_tenants.event_type = 'users.messages.pushnotification.Send'
LEFT JOIN
	datalake_braze.events_tenants AS open_tenants
		ON et.id_dispatch = open_tenants.id_dispatch
		AND et.id_braze = open_tenants.id_braze
		AND open_tenants.event_type = 'users.messages.pushnotification.Open'
LEFT JOIN
	datalake_braze.events_tenants AS bounce_tenants
		ON et.id_dispatch = bounce_tenants.id_dispatch
		AND et.id_braze = bounce_tenants.id_braze
		AND bounce_tenants.event_type = 'users.messages.pushnotification.Bounce'
WHERE
	et.event_channel = 'pushnotification'
GROUP BY
	1,2,3,4,5
