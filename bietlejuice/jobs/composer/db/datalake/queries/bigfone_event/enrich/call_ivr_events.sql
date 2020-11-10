SELECT
	id,
	GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.callSid') AS id_call,
	NULLIF(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.teravozCallId'),'') AS id_call_teravoz,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskChannelSid') AS id_channel,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from') AS from_number,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.to') AS to_number,
	event AS event_type,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskCanceledReason') AS task_cancelation_reason,
	steps,
	metadata,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskPriority') AS INT) AS task_priority,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.csat-1') AS INT) AS csat_1,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.csat-2') AS INT) AS csat_2,
	ts_created_local,
	ts_received_local,
	year,
	month,
	day
FROM datalake_bigfone.twilio_ivr_events
WHERE year = {year}
	AND month = {month}
	AND day = {day}
