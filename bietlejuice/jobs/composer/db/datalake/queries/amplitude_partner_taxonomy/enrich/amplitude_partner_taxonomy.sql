WITH
cr_utm AS (
	SELECT
		e.ts_event,
		e.id_device,
		CAST(GET_JSON_OBJECT(e.user_properties, '$.utm_campaign') AS string) AS utm_campaign,
		CAST(GET_JSON_OBJECT(e.user_properties, '$.utm_medium') AS string) AS utm_medium,
		CAST(GET_JSON_OBJECT(e.user_properties, '$.utm_source') AS string) AS utm_source,
		ROW_NUMBER() OVER(PARTITION BY id_device ORDER BY e.ts_event) rn_event,
		year,
		month,
		day
	FROM
		datalake_amplitude_clean.events e
	WHERE
		e.id_app = 283048
		AND e.event_type = 'register_form_completed'
		AND year = {year}
		AND month = {month}
		AND day = {day}
)
SELECT
	id_device,
	utm_campaign,
	utm_medium,
	utm_source,
	year,
	month,
	day
FROM
	cr_utm
WHERE
	rn_event = 1
GROUP BY 1,2,3,4,5,6,7