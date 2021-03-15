SELECT
	id_user_braze AS sk_braze_user,
	id_user_dispatch AS sk_user_dispatch,
	id_canvas AS sk_canvas,
	id_variant_canvas AS sk_variant_canvas,
	id_step_canvas AS sk_step_canvas,
	user_type,
	event_channel,
	ts_email_sent,
	ts_email_delivered,
	ts_email_bounced,
	ts_email_unsubscribed,
	ts_email_spammed,
	ts_push_sent,
	ts_push_bounced,
	ts_sms_sent,
	ts_sms_send_to_carried,
	ts_sms_delivered,
	ts_sms_rejected,
	ts_sms_delivery_failed,
	ts_webhook_sent,
	ts_inapp_impressioned,
	COUNT(DISTINCT ts_email_opened) AS total_email_opened,
	MIN(ts_email_opened) AS ts_email_first_opened,
	MAX(ts_email_opened) AS ts_email_last_opened,
	COUNT(DISTINCT ts_email_clicked) AS total_email_clicked,
	MIN(ts_email_clicked) AS ts_email_first_clicked,
	MAX(ts_email_clicked) AS ts_email_last_clicked,
	COUNT(DISTINCT ts_push_opened) AS total_push_opened,
	MIN(ts_push_opened) AS ts_push_first_opened,
	MAX(ts_push_opened) AS ts_push_last_opened,
	NOW() AS ts_load,
	year,
	month,
	day
FROM 
	datalake_braze_dispatches_user.owners_events
WHERE
	id_canvas IS NOT NULL
	AND year = {year}
	AND month = {month}
	AND day = {day}	
GROUP BY
	1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,year,month,day

UNION ALL

SELECT
	id_user_braze AS sk_braze_user,
	id_user_dispatch AS sk_user_dispatch,
	id_canvas AS sk_canvas,
	id_variant_canvas AS sk_variant_canvas,
	id_step_canvas AS sk_step_canvas,
	user_type,
	event_channel,
	ts_email_sent,
	ts_email_delivered,
	ts_email_bounced,
	ts_email_unsubscribed,
	ts_email_spammed,
	ts_push_sent,
	ts_push_bounced,
	ts_sms_sent,
	ts_sms_send_to_carried,
	ts_sms_delivered,
	ts_sms_rejected,
	ts_sms_delivery_failed,
	ts_webhook_sent,
	ts_inapp_impressioned,
	COUNT(DISTINCT ts_email_opened) AS total_email_opened,
	MIN(ts_email_opened) AS ts_email_first_opened,
	MAX(ts_email_opened) AS ts_email_last_opened,
	COUNT(DISTINCT ts_email_clicked) AS total_email_clicked,
	MIN(ts_email_clicked) AS ts_email_first_clicked,
	MAX(ts_email_clicked) AS ts_email_last_clicked,
	COUNT(DISTINCT ts_push_opened) AS total_push_opened,
	MIN(ts_push_opened) AS ts_push_first_opened,
	MAX(ts_push_opened) AS ts_push_last_opened,
	NOW() AS ts_load,
	year,
	month,
	day
FROM 
	datalake_braze_dispatches_user.tenants_events
WHERE
	id_canvas IS NOT NULL
	AND year = {year}
	AND month = {month}
	AND day = {day}	
GROUP BY
	1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,year,month,day
