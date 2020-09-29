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
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_quinto_messenger_raw.task
WHERE
    DATE(updated_at) = DATE('{year}-{month}-{day}')