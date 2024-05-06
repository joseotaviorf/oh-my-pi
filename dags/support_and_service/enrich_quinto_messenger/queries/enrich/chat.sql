SELECT
    id_chat,
    id_channel,
    id_session,
    source,
    session_status,
    ts_created,
    ts_updated
FROM
    datalake_quinto_messenger_clean.chat
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_chat ORDER BY ts_updated DESC) = 1
