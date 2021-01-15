WITH last_agent_events AS (
	SELECT
		COALESCE(
			GET_JSON_OBJECT(metadata,'$.event_data.WorkerSid'),
			GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.worker_sid')
		) AS id_agent,
		MAX(GET_JSON_OBJECT(metadata,'$.event_data.Sid')) AS id_last_event,
		MIN(ts_created_local) AS ts_first_event,
		MAX(ts_created_local) AS ts_last_event,
		year,
		month,
		day
	FROM
		datalake_bigfone_events.events
	WHERE
		provider = 'twilio'
		AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
		AND GET_JSON_OBJECT(metadata,'$.event_data.WorkerAttributes') IS NOT NULL
		AND year = {year}
		AND month = {month}
		AND day = {day}
	GROUP BY 1,5,6,7
)
SELECT
	lae.id_agent,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.email') as email,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.full_name') as full_name,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.location') as location,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.routing.skills') as skills,
	lae.ts_first_event,
	lae.ts_last_event,
	lae.year,
	lae.month,
	lae.day
FROM
	datalake_bigfone_events.events cfe
INNER JOIN last_agent_events lae
	ON GET_JSON_OBJECT(cfe.metadata,'$.event_data.Sid') = lae.id_last_event
WHERE
	cfe.provider = 'twilio'
	AND GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
	AND cfe.year = {year}
	AND cfe.month = {month}
	AND cfe.day = {day}
