WITH last_updated_chat AS (
    SELECT
        *
    FROM
        datalake_quinto_messenger_clean.chat
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
)

SELECT
    id AS id_chat,
    GET_JSON_OBJECT(attributes,'$.channel_sid') AS id_channel,
    id_source AS id_session,
    source,
    status AS session_status,
    ts_created,
    ts_updated
FROM
    last_updated_chat
