SELECT
    id_conversation AS sk_chat,
    channel_type AS channel,
    from_phone_number AS customer_phone,
    LOWER(channel_status) AS status,
    is_forwarded,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM datalake_quinto_messenger.channel
