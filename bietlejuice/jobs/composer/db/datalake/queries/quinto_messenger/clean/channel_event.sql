SELECT
    id,
    channel_id AS id_channel_external,
    event_type,
    event_payload,
    created_at AS ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.channelevent
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}