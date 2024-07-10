SELECT
    id,
    task_id AS id_task,
    event_id AS id_event,
    GET_JSON_OBJECT(event_payload,'$.TaskQueueSid') AS id_queue,
    GET_JSON_OBJECT(event_payload,'$.TaskQueueName') AS queue_name,
    GET_JSON_OBJECT(event_payload,'$.TaskChannelUniqueName') AS channel_name,
    event_type,
    event_payload,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.taskevent
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
