SELECT
    id,
    channel_id AS id_external,
    source_id AS id_source,
    source_uuid AS id_source_unique,
    channel_status,
    channel_attributes,
    channel_resource,
    channel_proxy,
    source,
    user_phone,
    created_at AS ts_created,
    updated_at as ts_updated,
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_quinto_messenger_raw.channel
WHERE
    DATE(updated_at) = DATE('{year}-{month}-{day}')
