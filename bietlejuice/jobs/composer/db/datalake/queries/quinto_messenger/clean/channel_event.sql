SELECT
    id,
    channel_id AS id_channel_external,
    event_type,
    event_payload,
    created_at AS ts_created,
    updated_at as ts_updated,
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_quinto_messenger_raw.channelevent
WHERE
    DATE(updated_at) = DATE('{year}-{month}-{day}')