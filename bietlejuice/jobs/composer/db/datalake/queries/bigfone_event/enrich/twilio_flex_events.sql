SELECT
	id,
	GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
	event,
	metadata,
	ts_created_local,
	ts_received_local,
	year,
	month,
	day
FROM datalake_bigfone_clean.events
WHERE provider = 'twilio'
	AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
	AND year = {year}
	AND month = {month}
	AND day = {day}
