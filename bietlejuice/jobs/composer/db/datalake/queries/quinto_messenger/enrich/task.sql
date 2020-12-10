WITH tasks AS (
	SELECT
		id_external,
		task_attributes,
		id_channel_external,
		task_status,
		assigned_to,
		seconds_to_first_response,
		ts_created,
		ts_updated,
		DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_extracted
	FROM datalake_quinto_messenger_clean.task
),
last_extracted_tasks AS (
	SELECT
		id_external,
		MAX(dt_extracted) AS dt_last_extracted
	FROM tasks
	GROUP BY 1
)
SELECT
	t.id_external AS id_task,
	t.id_channel_external AS id_channel,
	GET_JSON_OBJECT(t.task_attributes,'$.conversations.conversation_id') AS id_conversation,
	GET_JSON_OBJECT(t.assigned_to,'$.worker_sid') AS id_agent,
	GET_JSON_OBJECT(t.assigned_to,'$.worker_name') AS agent_email,
	GET_JSON_OBJECT(t.task_attributes,'$.channelType') AS channel_type_twilio,
	GET_JSON_OBJECT(t.task_attributes,'$.channel_type') AS channel_type_internal,
	t.task_status,
	GET_JSON_OBJECT(t.task_attributes,'$.status') AS channel_status,
	GET_JSON_OBJECT(t.task_attributes,'$.target') AS ticket_group_name,
	REGEXP_EXTRACT(GET_JSON_OBJECT(t.task_attributes,'$.from'),'(\\w+:)(.+)',2) AS from_phone_number,
	REGEXP_EXTRACT(GET_JSON_OBJECT(t.task_attributes,'$.twilioNumber'),'(\\w+:)(.+)',2) AS twilio_phone_number,
	REGEXP_EXTRACT(GET_JSON_OBJECT(t.task_attributes,'$.$.serviceNumber'),'(\\w+:)(.+)',2) AS service_phone_number,
	GET_JSON_OBJECT(t.task_attributes,'$.tagsByType.routing_tags') AS routing_tags,
	NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(t.task_attributes,'$.tagsByType.contact_theme_tag'),'(\\[")([a-z_]+)("\\])',2),'') AS contact_theme_tag,
	NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(t.task_attributes,'$.tagsByType.customer_type_tag'),'(\\[")([a-z_]+)("\\])',2),'') AS customer_type_tag,
	NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(t.task_attributes,'$.tagsByType.contact_motivation_tag'),'(\\[")([a-z_]+)("\\])',2),'') AS contact_motivation_tag,
	CAST(GET_JSON_OBJECT(t.task_attributes,'$.forwarding') AS BOOLEAN) AS is_forwarded,
	CAST(GET_JSON_OBJECT(task_attributes,'$.conversations.task_number') AS INT) as task_number,
	t.seconds_to_first_response,
	t.ts_created,
	t.ts_updated
FROM tasks t
INNER JOIN last_extracted_tasks let
	ON let.id_external = t.id_external
	AND let.dt_last_extracted = t.dt_extracted
