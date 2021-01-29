SELECT
	et.id_dispatch,
	et.id_user_braze,
	send_tenants.ts_event AS ts_webhook_sent
FROM 
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants send_tenants
		ON et.id_braze = send_tenants.id_braze
		AND send_tenants.event_type = 'users.messages.webhook.Send'
WHERE
	et.event_channel = 'webhook'
GROUP BY
	1,2,3
    
