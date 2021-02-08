SELECT
	et.id_dispatch,
	et.id_user_braze,
	et.event_channel,
	send_tenants.ts_event AS ts_email_sent,
	delivery_tenants.ts_event AS ts_email_delivered,
	open_tenants.ts_event AS ts_email_opened,
	click_tenants.ts_event AS ts_email_clicked,
	bounce_tenants.ts_event AS ts_email_bounced,
	spam_tenants.ts_event AS ts_email_spammed,
	unsubscribe_tenants.ts_event AS ts_email_unsubscribed,
	et.year,
	et.month,
	et.day
FROM 
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants AS send_tenants
		ON et.id_dispatch = send_tenants.id_dispatch
		AND et.id_user_braze = send_tenants.id_user_braze
		AND send_tenants.event_type = 'users.messages.email.Send'
LEFT JOIN
	datalake_braze.events_tenants AS delivery_tenants
		ON et.id_dispatch = delivery_tenants.id_dispatch
		AND et.id_user_braze = delivery_tenants.id_user_braze
		AND delivery_tenants.event_type = 'users.messages.email.Delivery'
LEFT JOIN
	datalake_braze.events_tenants AS open_tenants
		ON et.id_dispatch = open_tenants.id_dispatch
		AND et.id_user_braze = open_tenants.id_user_braze
		AND open_tenants.event_type = 'users.messages.email.Open'
LEFT JOIN
	datalake_braze.events_tenants AS click_tenants
		ON et.id_dispatch = click_tenants.id_dispatch
		AND et.id_user_braze = click_tenants.id_user_braze
		AND click_tenants.event_type = 'users.messages.email.Click'
LEFT JOIN
	datalake_braze.events_tenants AS bounce_tenants
		ON et.id_dispatch = bounce_tenants.id_dispatch
		AND et.id_user_braze = bounce_tenants.id_user_braze
		AND bounce_tenants.event_type IN ('users.messages.email.Bounce', 'users.messages.email.SoftBounce')
LEFT JOIN
	datalake_braze.events_tenants AS spam_tenants
		ON et.id_dispatch = spam_tenants.id_dispatch
		AND et.id_user_braze = spam_tenants.id_user_braze
		AND spam_tenants.event_type = 'users.messages.email.MarkAsSpam'
LEFT JOIN
	datalake_braze.events_tenants AS unsubscribe_tenants
		ON et.id_dispatch = unsubscribe_tenants.id_dispatch
		AND et.id_user_braze = unsubscribe_tenants.id_user_braze
		AND unsubscribe_tenants.event_type = 'users.messages.email.Unsubscribe'
WHERE
	et.event_channel = 'email'
	AND et.year = {year}
	AND et.month = {month}
	AND et.day = {day}
GROUP BY
	1,2,3,4,5,6,7,8,9,10,11,12,13
