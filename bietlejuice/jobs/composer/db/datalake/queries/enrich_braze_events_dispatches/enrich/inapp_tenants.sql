SELECT
	et.id_user_dispatch,
	et.id_user_braze,
	et.event_channel,
	impression_tenants.ts_event AS ts_inapp_impressioned,
-- 	click_tenants.ts_event AS ts_inapp_clicked,
	et.year,
	et.month,
	et.day
FROM 
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants AS impression_tenants
		ON et.id_user_dispatch = impression_tenants.id_user_dispatch
		AND impression_tenants.event_type = 'users.messages.inappmessage.Impression'
-- LEFT JOIN
-- 	datalake_braze.events_tenants AS click_tenants
-- 		ON et.id_user_dispatch = click_tenants.id_user_dispatch
-- 		AND click_tenants.event_type = 'users.messages.inappmessage.Click'
WHERE
	et.event_channel = 'inappmessage'
	AND et.year = {year}
	AND et.month = {month}
	AND et.day = {day}
GROUP BY
	1,2,3,4,5,6,7
