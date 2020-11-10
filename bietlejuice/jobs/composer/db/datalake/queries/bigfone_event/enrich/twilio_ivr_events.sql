SELECT
	id,
	GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
	event,
	metadata,
	GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.steps') AS steps,
	ts_created_local,
	ts_received_local,
	year,
	month,
	day
FROM datalake_bigfone_clean.events
WHERE provider = 'twilio'
	AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'IVR Events'
	AND year = {year}
	AND month = {month}
	AND day = {day}