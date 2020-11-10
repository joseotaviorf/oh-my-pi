WITH event_steps AS (
	SELECT
		id,
		id_event,
		EXPLODE(SPLIT(steps,'}},')) as step,
		year,
        month,
        day
	FROM datalake_bigfone.twilio_ivr_events
	WHERE year = {year}
        AND month = {month}
        AND day = {day}
)
SELECT
	id,
	id_event,
	REGEXP_EXTRACT(step,'([A-Za-z0-9_]+)',1) AS step_name,
	REGEXP_EXTRACT(step,'("event":")(\\w+)',2) AS event_type,
	CAST(REGEXP_EXTRACT(step,'("digits":")(\\d+)',2) AS INT) AS digits,
	FROM_UNIXTIME(CAST(REGEXP_EXTRACT(step,'("timestamp":)(\\d+)',2) AS BIGINT)/1000) AS ts_created,
	year,
	month,
	day
FROM event_steps
