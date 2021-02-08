SELECT
	eo.id_dispatch,
	eo.id_user_braze,
	eo.event_channel,
	send_owners.ts_event AS ts_webhook_sent,
	eo.year,
	eo.month,
	eo.day
FROM 
	datalake_braze.events_owners AS eo
LEFT JOIN
	datalake_braze.events_owners AS send_owners
		ON eo.id_user_braze = send_owners.id_user_braze
		AND send_owners.event_type = 'users.messages.webhook.Send'
WHERE
	eo.event_channel = 'webhook'
	AND eo.year = {year}
	AND eo.month = {month}
	AND eo.day = {day}
GROUP BY
	1,2,3,4,5,6,7
    
