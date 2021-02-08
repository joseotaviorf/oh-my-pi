SELECT
	et.id_dispatch,
	et.id_user_braze,
	et.event_channel,
	send_tenants.ts_event AS ts_sms_sent,
	sendtocarrier_tenants.ts_event AS ts_sms_send_to_carried,
	delivery_tenants.ts_event AS ts_sms_delivered,
	rejection_tenants.ts_event AS ts_sms_rejected,
	deliveryfailure_tenants.ts_event AS ts_sms_delivery_failed,
	et.year,
	et.month,
	et.day
FROM 
	datalake_braze.events_tenants AS et
LEFT JOIN
	datalake_braze.events_tenants AS send_tenants
		ON et.id_dispatch = send_tenants.id_dispatch 
		AND et.id_user_braze = send_tenants.id_user_braze 
		AND send_tenants.event_type = 'users.messages.sms.Send'
LEFT JOIN
	datalake_braze.events_tenants AS sendtocarrier_tenants
		ON et.id_dispatch = sendtocarrier_tenants.id_dispatch 
		AND et.id_user_braze = sendtocarrier_tenants.id_user_braze 
		AND sendtocarrier_tenants.event_type = 'users.messages.sms.SendToCarrier'
LEFT JOIN
	datalake_braze.events_tenants AS delivery_tenants
		ON et.id_dispatch = delivery_tenants.id_dispatch 
		AND et.id_user_braze = delivery_tenants.id_user_braze
		AND delivery_tenants.event_type = 'users.messages.sms.Delivery'
LEFT JOIN
	datalake_braze.events_tenants AS rejection_tenants
		ON et.id_dispatch = rejection_tenants.id_dispatch 
		AND et.id_user_braze = rejection_tenants.id_user_braze 
		AND rejection_tenants.event_type = 'users.messages.sms.Rejection'
LEFT JOIN
	datalake_braze.events_tenants AS deliveryfailure_tenants
		ON et.id_dispatch = deliveryfailure_tenants.id_dispatch 
		AND et.id_user_braze = deliveryfailure_tenants.id_user_braze 
		AND deliveryfailure_tenants.event_type = 'users.messages.sms.DeliveryFailure'
WHERE
	et.event_channel = 'sms'
	AND et.year = {year}
	AND et.month = {month}
	AND et.day = {day}
GROUP BY
	1,2,3,4,5,6,7,8,9,10,11
