SELECT
	id,
	GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
	GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') AS id_reservation,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskQueueSid') AS id_task_queue,
	GET_JSON_OBJECT(metadata,'$.event_data.TransferTo') AS id_task_queue_transferred,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.call_sid') AS id_call,
	COALESCE(GET_JSON_OBJECT(metadata,'$.event_data.WorkerSid'),
		GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.worker_sid')) AS id_agent,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.TransInitiatingWorkerSid') AS id_agent_transferred,
	NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from'),'(sip:)?([0-9+]+)@?',2),'') AS from_number,
	NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.outbound_to'),'(sip:)?([0-9+]+)@?',2),'') AS to_number,
	CASE
		WHEN GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.direction') = 'inbound' 
			THEN REGEXP_REPLACE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from'),'(sip:)?([0-9+]+)@?',2),''),'(^\\+?55)|(\\D*)','')
		WHEN GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.direction') = 'outbound' 
			THEN REGEXP_REPLACE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.outbound_to'),'(sip:)?([0-9+]+)@?',2),''),'(^\\+?55)|(\\D*)','')
	END AS customer_phone,
	GET_JSON_OBJECT(metadata,'$.event_data.WorkerName') AS agent_email,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.target') AS department_name,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskQueueName') AS task_queue_name,
	event AS event_type,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.direction') AS direction,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.BPO') AS location,
	GET_JSON_OBJECT(metadata,'$.event_data.Reason') AS reason,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.comment') AS comment,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.hasWrapup') AS BOOLEAN) AS has_wrapup,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.hasCsat') AS BOOLEAN) AS has_csat,
	metadata,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskPriority') AS INT) AS task_priority,
	CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.waiting_time') AS INT) AS seconds_waiting_time,
	ts_created_local,
	ts_received_local,
	TO_TIMESTAMP(GET_JSON_OBJECT(metadata,'$.event_data.TransferStarted')) AS ts_transfer_started,
	CASE
		WHEN GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.direction') = 'inbound' AND event = 'task.wrapup' THEN ts_created_local
	END AS ts_wrapup_event_local,
	CASE
		WHEN GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.direction') = 'inbound' AND event = 'task.wrapup' THEN UNIX_TIMESTAMP(ts_created_local)
	END AS ts_wrapup_event_local_unix,
	UNIX_TIMESTAMP(ts_created_local) AS ts_created_local_unix,
	year,
	month,
	day
FROM
	datalake_bigfone_events.events
WHERE
	provider = 'twilio'
	AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
	AND year = {year}
	AND month = {month}
	AND day = {day}
