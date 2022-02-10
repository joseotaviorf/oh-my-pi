SELECT
    id, 
    task_id AS id_task_external,
    event_id AS id_event,
    event_type,
    event_payload,
    created_at AS ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.taskevent
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}