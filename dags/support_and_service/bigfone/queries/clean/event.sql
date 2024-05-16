SELECT
    id,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
    GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') AS id_reservation,
    GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskQueueSid') AS id_queue,
    GET_JSON_OBJECT(metadata,'$.event_data.WorkerSid') AS id_worker,
    call_id AS twilio_sid,
    type AS event_type,
    GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') AS workflow_name,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.from') AS from_number,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.outbound_to') AS to_number,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.direction') AS direction,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.channelType') AS channel_type,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.BPO') AS bpo_name,
    GET_JSON_OBJECT(metadata,'$.event_data.TaskQueueName') AS queue_name,
    GET_JSON_OBJECT(metadata,'$.event_data.WorkerAttributes.email') AS worker_email,
    CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.csat-1') AS INT) AS csat_1,
    CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.csat-2') AS INT) AS csat_2,
    CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.csat-3') AS INT) AS csat_3,
    CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.scheduled') AS BOOLEAN) AS is_scheduled,
    CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.hasWrapup') AS BOOLEAN) AS has_wrapup,
    CAST(GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.hasCsat') AS BOOLEAN) AS has_csat,
    metadata,
    provider,
    event_timestamp AS ts_created,
    received_timestamp AS ts_received,
    year,
    month,
    day
FROM
    datalake_bigfone_raw.event
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
