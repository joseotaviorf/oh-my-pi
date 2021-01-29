SELECT
	eo.id_dispatch,
	eo.id_user_braze,
	send_owners.ts_event AS ts_email_sent,
	delivery_owners.ts_event AS ts_email_delivered,
	open_owners.ts_event AS ts_email_opened,
	click_owners.ts_event AS ts_email_clicked,
	bounce_owners.ts_event AS ts_email_bounced,
	spam_owners.ts_event AS ts_email_spammed,
	unsubscribe_owners.ts_event AS ts_email_unsubscribed
FROM 
	datalake_braze.events_owners AS eo
LEFT JOIN
	datalake_braze.events_owners AS send_owners
		ON eo.id_dispatch = send_owners.id_dispatch
		AND eo.id_user_braze = send_owners.id_user_braze
		AND send_owners.event_type = 'users.messages.email.Send'
LEFT JOIN
	datalake_braze.events_owners AS delivery_owners
		ON eo.id_dispatch = delivery_owners.id_dispatch
		AND eo.id_user_braze = delivery_owners.id_user_braze
		AND delivery_owners.event_type = 'users.messages.email.Delivery'
LEFT JOIN
	datalake_braze.events_owners AS open_owners
		ON eo.id_dispatch = open_owners.id_dispatch
		AND eo.id_user_braze = open_owners.id_user_braze
		AND open_owners.event_type = 'users.messages.email.Open'
LEFT JOIN
	datalake_braze.events_owners AS click_owners
		ON eo.id_dispatch = click_owners.id_dispatch
		AND eo.id_user_braze = click_owners.id_user_braze
		AND click_owners.event_type = 'users.messages.email.Click'
LEFT JOIN
	datalake_braze.events_owners AS bounce_owners
		ON eo.id_dispatch = bounce_owners.id_dispatch
		AND eo.id_user_braze = bounce_owners.id_user_braze
		AND bounce_owners.event_type IN ('users.messages.email.Bounce', 'users.messages.email.SoftBounce')
LEFT JOIN
	datalake_braze.events_owners AS spam_owners
		ON eo.id_dispatch = spam_owners.id_dispatch
		AND eo.id_user_braze = spam_owners.id_user_braze
		AND spam_owners.event_type = 'users.messages.email.MarkAsSpam'
LEFT JOIN
	datalake_braze.events_owners AS unsubscribe_owners
		ON eo.id_dispatch = unsubscribe_owners.id_dispatch
		AND eo.id_user_braze = unsubscribe_owners.id_user_braze
		AND unsubscribe_owners.event_type = 'users.messages.email.Unsubscribe'
WHERE
	eo.event_channel = 'email'
GROUP BY
	1,2,3,4,5,6,7,8,9
