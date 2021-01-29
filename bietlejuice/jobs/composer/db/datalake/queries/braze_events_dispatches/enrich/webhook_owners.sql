SELECT
	eo.id_dispatch,
	eo.id_user_braze,
	send_owners.ts_event AS ts_webhook_sent
FROM 
	datalake_braze.events_owners AS eo
LEFT JOIN
	datalake_braze.events_owners AS send_owners
		ON eo.id_braze = send_owners.id_braze
		AND send_owners.event_type = 'users.messages.webhook.Send'
WHERE
	eo.event_channel = 'webhook'
GROUP BY
	1,2,3
    
