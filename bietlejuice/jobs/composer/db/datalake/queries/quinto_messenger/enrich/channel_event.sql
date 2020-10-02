WITH channel_events AS (
	SELECT
		id,
		id_channel_external,
		event_type,
		event_payload,
		ts_created,
		ts_updated,
		DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_extracted
	FROM datalake_quinto_messenger_clean.channel_event
),
last_extracted_events AS (
	SELECT
		id,
		MAX(dt_extracted) AS dt_last_extracted
	FROM channel_events
	GROUP BY 1
)
SELECT
	ce.id AS id_channel_event,
	GET_JSON_OBJECT(ce.event_payload,'$.MessageSid') AS id_message,
	ce.id_channel_external AS id_channel,
	ce.event_type,
	GET_JSON_OBJECT(ce.event_payload,'$.Source') AS source,
	REGEXP_EXTRACT(GET_JSON_OBJECT(ce.event_payload,'$.From'),'(\\w+:)(.+)',2) AS from_contact,
	CAST(GET_JSON_OBJECT(ce.event_payload,'$.Index') AS INT) AS message_index,
	ce.ts_created,
	ce.ts_updated
FROM channel_events ce
INNER JOIN last_extracted_events lee
	ON lee.id = ce.id
	AND lee.dt_last_extracted = ce.dt_extracted