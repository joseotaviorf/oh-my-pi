SELECT
	id,
	GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.callSid') AS id_call,
	NULLIF(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.teravozCallId'),'') AS id_call_teravoz,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskChannelSid') AS id_channel,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from') AS from_number,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.to') AS to_number,
	REGEXP_REPLACE(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from'),'(^\\+?55)|(\\D*)','') AS customer_phone,
	event AS event_type,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskCanceledReason') AS task_cancelation_reason,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.steps') AS steps,
	metadata,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskPriority') AS INT) AS task_priority,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.csat-1') AS INT) AS csat_1,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.csat-2') AS INT) AS csat_2,
	ts_created_local,
	ts_received_local,
	UNIX_TIMESTAMP(ts_created_local) AS ts_created_local_unix,
	year,
	month,
	day
FROM
	datalake_bigfone_events.events
WHERE
	provider = 'twilio'
	AND (
		GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'IVR Events'
		OR CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.scheduled') AS BOOLEAN) = TRUE
	)
	AND year = {year}
	AND month = {month}
	AND day = {day}
