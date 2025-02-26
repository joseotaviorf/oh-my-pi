SELECT
    id AS id_chat,
    external_id AS id_external,
    source_id AS id_session,
    GET_JSON_OBJECT(attributes,'$.channel_sid') AS id_channel,
    attributes,
    source,
    source_identity,
    status AS session_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.chat
