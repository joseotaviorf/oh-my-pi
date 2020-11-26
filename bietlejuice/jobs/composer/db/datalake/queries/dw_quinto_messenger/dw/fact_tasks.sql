SELECT  
    t.id_task AS sk_task,
    c.id_conversation AS sk_chat,
    t.id_agent AS sk_quinto_messenger_agent,
    COALESCE(CAST(date_format(t.ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_created_date,
    t.is_forwarded,
    t.seconds_to_first_response AS seconds_first_reply,
    t.task_number
FROM datalake_quinto_messenger.task t
INNER JOIN datalake_quinto_messenger.channel c
    ON t.id_channel = c.id_channel
