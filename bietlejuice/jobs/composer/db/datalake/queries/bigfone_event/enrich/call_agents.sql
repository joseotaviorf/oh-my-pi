WITH last_agent_events AS (
	SELECT
		COALESCE(GET_JSON_OBJECT(metadata,'$.event_data.WorkerSid'),
			GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.worker_sid')) AS id_agent,
		MAX(id_event) AS id_last_event,
		year,
		month,
		day
	FROM datalake_bigfone.call_flex_events
	WHERE GET_JSON_OBJECT(metadata,'$.event_data.WorkerAttributes') IS NOT NULL
		AND year = {year}
		AND month = {month}
		AND day = {day}
	GROUP BY 1,3,4,5
)
SELECT
	lae.id_agent,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.email') as email,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.full_name') as full_name,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.location') as location,
	GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkerAttributes.routing.skills') as skills,
	lae.year,
	lae.month,
	lae.day
FROM datalake_bigfone.call_flex_events cfe
INNER JOIN last_agent_events lae
	ON cfe.id_event = lae.id_last_event
WHERE cfe.year = {year}
	AND cfe.month = {month}
	AND cfe.day = {day}
