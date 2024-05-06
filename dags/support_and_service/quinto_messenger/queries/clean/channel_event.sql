SELECT
    id,
    channel_id AS id_channel,
    GET_JSON_OBJECT(event_payload,'$.MessageSid') AS id_message,
    GET_JSON_OBJECT(event_payload,'$.Source') AS source,
    GET_JSON_OBJECT(event_payload,'$.From') AS from_phone_number,
    GET_JSON_OBJECT(event_payload,'$.Body') AS message_body,
    GET_JSON_OBJECT(event_payload,'$.Index') AS message_index,
    event_type,
    event_payload,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.channelevent
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
