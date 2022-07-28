SELECT
	et.id_user_dispatch,
	et.id_user_braze,
	et.id_user,
	et.event_channel,
	send_tenants.ts_event AS ts_webhook_sent,
	et.year,
	et.month,
	et.day
FROM 
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants send_tenants
		ON et.id_user_dispatch = send_tenants.id_user_dispatch
		AND send_tenants.event_type = 'users.messages.webhook.Send'
WHERE
	et.event_channel = 'webhook'
	AND et.year = {year}
	AND et.month = {month}
	AND et.day = {day}
GROUP BY
	1,2,3,4,5,6,7,8
    
