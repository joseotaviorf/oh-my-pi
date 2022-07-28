SELECT
    id,
    task_id AS id_external,
    channel_id AS id_channel_external,
    task_status,
    task_attributes,
    task_resource,
    assigned_to, 
    seconds_to_first_response,
    created_at AS ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.task
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}