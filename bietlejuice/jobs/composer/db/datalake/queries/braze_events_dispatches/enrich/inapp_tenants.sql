SELECT
	et.id_dispatch,
	et.id_user_braze,
	impression_tenants.ts_event AS ts_inapp_impressioned,
	click_tenants.ts_event AS ts_inapp_clicked
FROM 
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants AS impression_tenants
		ON et.id_braze = impression_tenants.id_braze
		AND impression_tenants.event_type = 'users.messages.inappmessage.Impression'
LEFT JOIN
	datalake_braze.events_tenants AS click_tenants
		ON et.id_braze = click_tenants.id_braze
		AND click_tenants.event_type = 'users.messages.inappmessage.Click'
WHERE
	et.event_channel = 'inappmessage'
GROUP BY
	1,2,3,4
