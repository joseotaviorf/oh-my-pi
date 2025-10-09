SELECT DISTINCT
    m.id_session,
    m.id_sauron_session,
    m.id_external,
    m.id_ticket,
    m.id_user,
    m.bot,
    m.status,
    m.first_queue,
    m.last_queue,
    s.name,
    s.value,
    CASE
        WHEN s.value = 1 AND s.value IS NOT NULL THEN True
        ELSE False
    END AS flag_eval_matthew_in_chat,
    CASE
        WHEN s.value = 1 AND s.value IS NOT NULL THEN 'Matthew in Chat'
        WHEN m.bot = 'matthew' THEN 'Matthew in Whatsapp'
        ELSE 'Wall-e'
    END AS ai_agent_source,
    m.is_escalation,
    DATE(m.ts_created) AS dt_session_created,
    m.ts_created,
    m.ts_updated
FROM
    datalake_chatbot.sessions as m
LEFT JOIN
    datalake_langfuse_clean.scores s
        ON s.id_session = m.id_external
        AND s.name = 'SessionContainsMatthewAgentEvaluator'
WHERE (bot = 'matthew' OR (bot = 'wall-e'))
