WITH event_steps AS (
	SELECT
		id,
		GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
		GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.callSid') AS id_call,
		GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
		GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.steps') AS steps,
		year,
		month,
		day
	FROM
		datalake_bigfone_events.events
	WHERE
		provider = 'twilio'
		AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'IVR Events'
		AND GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.steps') IS NOT NULL
		AND year = {year}
		AND month = {month}
		AND day = {day}
),
event_step_by_step AS (
	SELECT
		id,
		id_event,
		id_call,
		id_task,
		EXPLODE(SPLIT(steps,'}},')) as step
	FROM
		event_steps
)
SELECT
	es.id,
	es.id_event,
	es.id_call,
	es.id_task,
	REGEXP_EXTRACT(esbs.step,'([A-Za-z0-9_]+)',1) AS step_name,
	REGEXP_EXTRACT(esbs.step,'("event":")(\\w+)',2) AS event_type,
	CAST(REGEXP_EXTRACT(esbs.step,'("digits":")(\\d+)',2) AS INT) AS digits,
	FROM_UNIXTIME(CAST(REGEXP_EXTRACT(esbs.step,'("timestamp":)(\\d+)',2) AS BIGINT)/1000) AS ts_created,
	es.year,
	es.month,
	es.day
FROM
	event_steps es
INNER JOIN
	event_step_by_step esbs
		ON esbs.id = es.id
			AND	esbs.id_event = es.id_event
			AND	esbs.id_call = es.id_call
			AND	esbs.id_task = es.id_task
