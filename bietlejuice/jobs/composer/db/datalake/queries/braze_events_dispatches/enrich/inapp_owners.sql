SELECT
	eo.id_dispatch,
	eo.id_user_braze,
	impression_owners.ts_event AS ts_inapp_impressioned,
	click_owners.ts_event AS ts_inapp_clicked
FROM 
	datalake_braze.events_owners AS eo
LEFT JOIN
	datalake_braze.events_owners AS impression_owners
		ON eo.id_braze = impression_owners.id_braze
		AND impression_owners.event_type = 'users.messages.inappmessage.Impression'
LEFT JOIN
	datalake_braze.events_owners AS click_owners
		ON eo.id_braze = click_owners.id_braze
		AND click_owners.event_type = 'users.messages.inappmessage.Click'
WHERE
	eo.event_channel = 'inappmessage'
GROUP BY
	1,2,3,4
