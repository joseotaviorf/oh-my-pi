WITH twilio_date AS (
    SELECT
        id_task,
        MAX(ts_created) AS ts_twilio_created,
        MAX(ts_updated) AS ts_twilio_updated
    FROM
        datalake_quinto_messenger_clean.task_event AS te
    WHERE
        event_type='reservation.accepted'
    GROUP BY 1
)
SELECT
	te.id AS id_task_event,
	te.id_task,
	GET_JSON_OBJECT(te.event_payload,'$.TaskChannelSid') AS id_channel,
	GET_JSON_OBJECT(te.event_payload,'$.TaskQueueSid') AS id_task_queue,
	te.event_type AS type,
	GET_JSON_OBJECT(te.event_payload,'$.TaskQueueName') AS task_queue_name,
	GET_JSON_OBJECT(te.event_payload,'$.TaskChannelUniqueName') AS channel_name,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.full_name') AS agent_full_name,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.email') AS agent_email,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.skills') AS agent_skills,
	GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.location') AS agent_location,
	GET_JSON_OBJECT(te.event_payload,'$.TaskAssignmentStatus') AS task_assignment_status,
	GET_JSON_OBJECT(te.event_payload,'$.TaskCompletedReason') AS task_completion_reason,
	CAST(GET_JSON_OBJECT(te.event_payload,'$.TaskPriority') AS INT) AS task_priority,
	te.ts_created,
	te.ts_updated,
	ted.ts_twilio_created,
	ted.ts_twilio_updated,
	FROM_UTC_TIMESTAMP(ts_created, 'America/Sao_Paulo') AS ts_created_local,
	FROM_UTC_TIMESTAMP(ts_updated, 'America/Sao_Paulo') AS ts_updated_local,
	FROM_UTC_TIMESTAMP(ts_twilio_created, 'America/Sao_Paulo') AS ts_twilio_created_local,
	FROM_UTC_TIMESTAMP(ts_twilio_updated, 'America/Sao_Paulo') AS ts_twilio_updated_local
FROM
	datalake_quinto_messenger_clean.task_event AS te
LEFT JOIN
    twilio_date AS ted
    	ON te.id_task = ted.id_task
QUALIFY
	ROW_NUMBER() OVER(PARTITION BY te.id ORDER BY te.year DESC, te.month DESC, te.day DESC) = 1
