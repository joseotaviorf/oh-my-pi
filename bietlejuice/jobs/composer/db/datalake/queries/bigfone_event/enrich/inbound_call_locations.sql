WITH last_location_events AS (
	SELECT
		GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.call_sid') AS id_call,
		MAX(id_event) AS id_last_event
	FROM datalake_bigfone.call_flex_events
	WHERE GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from_city') IS NOT NULL
		AND year = {year}
		AND month = {month}
		AND day = {day}
	GROUP BY 1
)
SELECT
	lle.id_call,
	NULLIF(GET_JSON_OBJECT(cfe.metadata,'$.event_data.TaskAttributes.from_city'),'') AS from_city,
	NULLIF(GET_JSON_OBJECT(cfe.metadata,'$.event_data.TaskAttributes.from_state'),'') AS from_state,
	NULLIF(GET_JSON_OBJECT(cfe.metadata,'$.event_data.TaskAttributes.from_country'),'') AS from_country
FROM datalake_bigfone.call_flex_events cfe
INNER JOIN last_location_events lle
	ON cfe.id_event = lle.id_last_event
WHERE cfe.year = {year}
	AND cfe.month = {month}
	AND cfe.day = {day}
