WITH task_events AS (
	SELECT
		id_event,
		id_task_external,
		event_type,
		event_payload,
		ts_created,
		ts_updated,
		DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_extracted
	FROM datalake_quinto_messenger_clean.task_event
),
last_extracted_events AS (
	SELECT
		id_event,
		MAX(dt_extracted) AS dt_last_extracted
	FROM task_events
	GROUP BY 1
)
SELECT
	te.id_event AS id_task_event,
	te.id_task_external AS id_task,
	GET_JSON_OBJECT(te.event_payload,'$.TaskChannelSid') AS id_channel,
	GET_JSON_OBJECT(te.event_payload,'$.TaskQueueSid') AS id_task_queue,
	te.event_type AS type,
	GET_JSON_OBJECT(te.event_payload,'$.TaskQueueName') AS task_queue_name,
	GET_JSON_OBJECT(te.event_payload,'$.TaskChannelUniqueName') AS channel_name,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.full_name') as agent_full_name,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.email') as agent_email,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.skills') as agent_skills,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.location') as agent_location,
	GET_JSON_OBJECT(te.event_payload,'$.TaskAssignmentStatus') AS task_assignment_status,
	GET_JSON_OBJECT(te.event_payload,'$.TaskCompletedReason') AS task_completion_reason,
	CAST(GET_JSON_OBJECT(te.event_payload,'$.TaskPriority') AS INT) AS task_priority,
	te.ts_created,
	te.ts_updated
FROM task_events te
INNER JOIN last_extracted_events lev
	ON lev.id_event = te.id_event
	AND lev.dt_last_extracted = te.dt_extracted
