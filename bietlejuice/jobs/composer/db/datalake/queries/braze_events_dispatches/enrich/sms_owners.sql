SELECT
	eo.id_dispatch,
	eo.id_user_braze,
	eo.event_channel,
	send_owners.ts_event AS ts_sms_sent,
	sendtocarrier_owners.ts_event AS ts_sms_send_to_carried,
	delivery_owners.ts_event AS ts_sms_delivered,
	rejection_owners.ts_event AS ts_sms_rejected,
	deliveryfailure_owners.ts_event AS ts_sms_delivery_failed,
	eo.year,
	eo.month,
	eo.day
FROM 
	datalake_braze.events_owners AS eo
LEFT JOIN
	datalake_braze.events_owners AS send_owners
		ON eo.id_dispatch = send_owners.id_dispatch 
		AND eo.id_user_braze = send_owners.id_user_braze 
		AND send_owners.event_type = 'users.messages.sms.Send'
LEFT JOIN
	datalake_braze.events_owners AS sendtocarrier_owners
		ON eo.id_dispatch = sendtocarrier_owners.id_dispatch 
		AND eo.id_user_braze = sendtocarrier_owners.id_user_braze 
		AND sendtocarrier_owners.event_type = 'users.messages.sms.SendToCarrier'
LEFT JOIN
	datalake_braze.events_owners AS delivery_owners
		ON eo.id_dispatch = delivery_owners.id_dispatch
		AND eo.id_user_braze = delivery_owners.id_user_braze
		AND delivery_owners.event_type = 'users.messages.sms.Delivery'
LEFT JOIN
	datalake_braze.events_owners AS rejection_owners
		ON eo.id_dispatch = rejection_owners.id_dispatch
		AND eo.id_user_braze = rejection_owners.id_user_braze
		AND rejection_owners.event_type = 'users.messages.sms.Rejection'
LEFT JOIN
	datalake_braze.events_owners AS deliveryfailure_owners
		ON eo.id_dispatch = deliveryfailure_owners.id_dispatch
		AND eo.id_user_braze = deliveryfailure_owners.id_user_braze
		AND deliveryfailure_owners.event_type = 'users.messages.sms.DeliveryFailure'
WHERE
	eo.event_channel = 'sms'
	AND eo.year = {year}
	AND eo.month = {month}
	AND eo.day = {day}
GROUP BY
	1,2,3,4,5,6,7,8,9,10,11
