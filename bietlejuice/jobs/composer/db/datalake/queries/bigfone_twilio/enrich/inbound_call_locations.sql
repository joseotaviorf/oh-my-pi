WITH last_location_events AS (
	SELECT
		GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.call_sid') AS id_call,
		MAX(GET_JSON_OBJECT(metadata,'$.event_data.Sid')) AS id_last_event,
		year,
		month,
		day
	FROM
		datalake_bigfone_events.events
	WHERE
		provider = 'twilio'
		AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
		AND GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from_city') IS NOT NULL
		AND year = {year}
		AND month = {month}
		AND day = {day}
	GROUP BY 1,3,4,5
)
SELECT
	lle.id_call,
	NULLIF(GET_JSON_OBJECT(cfe.metadata,'$.event_data.TaskAttributes.from_city'),'') AS from_city,
	NULLIF(GET_JSON_OBJECT(cfe.metadata,'$.event_data.TaskAttributes.from_state'),'') AS from_state,
	NULLIF(GET_JSON_OBJECT(cfe.metadata,'$.event_data.TaskAttributes.from_country'),'') AS from_country,
	lle.year,
	lle.month,
	lle.day
FROM
	datalake_bigfone_events.events cfe
INNER JOIN
	last_location_events lle
		ON GET_JSON_OBJECT(cfe.metadata,'$.event_data.Sid') = lle.id_last_event
WHERE
	cfe.provider = 'twilio'
	AND GET_JSON_OBJECT(cfe.metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
	AND cfe.year = {year}
	AND cfe.month = {month}
	AND cfe.day = {day}
