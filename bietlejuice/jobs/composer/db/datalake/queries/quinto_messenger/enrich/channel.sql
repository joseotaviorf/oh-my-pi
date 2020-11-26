WITH channels AS (
	SELECT
		id_external,
		id_source,
		id_source_unique,
		channel_status,
		channel_attributes,
		channel_resource,
		source,
		ts_created,
		ts_updated,
		DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_extracted
	FROM datalake_quinto_messenger_clean.channel
),
last_extracted_channels AS (
	SELECT
		id_external,
		MAX(dt_extracted) AS dt_last_extracted
	FROM channels
	GROUP BY 1
)
SELECT
	c.id_external AS id_channel,
	c.id_source,
	c.id_source_unique AS id_conversation,
	c.source,
	GET_JSON_OBJECT(c.channel_attributes,'$.channel_type') AS channel_type,
	c.channel_status,
	REGEXP_EXTRACT(GET_JSON_OBJECT(c.channel_attributes,'$.from'),'(\\w+:)(.+)',2) AS from_phone_number,
	REGEXP_EXTRACT(GET_JSON_OBJECT(c.channel_attributes,'$.twilioNumber'),'(\\w+:)(.+)',2) AS twilio_phone_number,
	REGEXP_EXTRACT(GET_JSON_OBJECT(c.channel_attributes,'$.serviceNumber'),'(\\w+:)(.+)',2) AS service_phone_number,
	CAST(GET_JSON_OBJECT(c.channel_attributes,'$.forwarding') AS BOOLEAN) AS is_forwarded,
	CAST(GET_JSON_OBJECT(c.channel_resource,'$.messages_count') AS INT) AS number_of_messages,
	CAST(GET_JSON_OBJECT(c.channel_resource,'$.members_count') AS INT) AS number_of_members,
	UNIX_TIMESTAMP(c.ts_updated) - UNIX_TIMESTAMP(c.ts_created) AS seconds_duration,
	c.ts_created,
	c.ts_updated
FROM channels c
INNER JOIN last_extracted_channels lec
	ON lec.id_external = c.id_external
	AND lec.dt_last_extracted = c.dt_extracted
