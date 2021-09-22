SELECT
	eo.id_user_dispatch,
	eo.id_user_braze,
	eo.id_user,
	eo.event_channel,
	send_owners.ts_event AS ts_push_sent,
	open_owners.ts_event AS ts_push_opened,
	bounce_owners.ts_event AS ts_push_bounced,
	eo.year,
	eo.month,
	eo.day
FROM
	datalake_braze.events_owners AS eo
LEFT JOIN
	datalake_braze.events_owners AS send_owners
		ON eo.id_user_dispatch = send_owners.id_user_dispatch
		AND send_owners.event_type = 'users.messages.pushnotification.Send'
LEFT JOIN
	datalake_braze.events_owners AS open_owners
		ON eo.id_user_dispatch = open_owners.id_user_dispatch
		AND open_owners.event_type = 'users.messages.pushnotification.Open'
LEFT JOIN
	datalake_braze.events_owners AS bounce_owners
		ON eo.id_user_dispatch = bounce_owners.id_user_dispatch
		AND bounce_owners.event_type = 'users.messages.pushnotification.Bounce'
WHERE
	eo.event_channel = 'pushnotification'
	AND eo.year = {year}
	AND eo.month = {month}
	AND eo.day = {day}
GROUP BY
	1,2,3,4,5,6,7,8,9,10
