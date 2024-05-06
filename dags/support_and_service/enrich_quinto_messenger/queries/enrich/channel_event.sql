WITH last_extracted_events AS (
	SELECT
		id,
		MAX(DATE(CONCAT(CAST(ce.year AS VARCHAR(4)), '-', CAST(ce.month AS VARCHAR(2)), '-', CAST(ce.day AS VARCHAR(2))))) AS dt_last_extracted
	FROM
		datalake_quinto_messenger_clean.channel_event AS ce
	GROUP BY 1
)
SELECT
	ce.id AS id_channel_event,
	GET_JSON_OBJECT(ce.event_payload,'$.MessageSid') AS id_message,
	ce.id_channel,
	ce.event_type,
	GET_JSON_OBJECT(ce.event_payload,'$.Source') AS source,
	NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(ce.event_payload,'$.From'),'(\\w+:)(.+)',2),'') AS from_phone_number,
	CASE
		WHEN GET_JSON_OBJECT(ce.event_payload,'$.From') NOT RLIKE 'whatsapp:\\+\\d+' THEN GET_JSON_OBJECT(ce.event_payload,'$.From')
	END AS from_email,
	CAST(GET_JSON_OBJECT(ce.event_payload,'$.Index') AS INT) AS message_index,
	ce.ts_created,
	ce.ts_updated
FROM
	datalake_quinto_messenger_clean.channel_event AS ce
INNER JOIN last_extracted_events lee
	ON lee.id = ce.id
	AND lee.dt_last_extracted = DATE(CONCAT(CAST(ce.year AS VARCHAR(4)), '-', CAST(ce.month AS VARCHAR(2)), '-', CAST(ce.day AS VARCHAR(2))))
