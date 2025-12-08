WITH base AS (
    SELECT DISTINCT
        m.id_session,
        m.id_sauron_session,
        m.id_langfuse_session AS id_external,
        m.id_ticket,
        m.id_user,
        m.bot,
        m.first_queue,
        m.last_queue,
        s.name,
        s.value,
        s2.value as matthew_version,
        CASE
            WHEN (s.value = 1 AND s.value IS NOT NULL) OR (CAST(s2.value AS DOUBLE) <> 0 AND s2.value IS NOT NULL) THEN True
            ELSE False
        END AS flag_eval_matthew_in_chat,
        CASE
            WHEN m.bot = 'matthew' THEN 'Matthew in Whatsapp'
            WHEN m.bot = 'wall-e' AND (s.value = 1 AND s.value IS NOT NULL) OR (CAST(s2.value AS DOUBLE) <> 0 AND s2.value IS NOT NULL) THEN 'Matthew in Chat'
            ELSE 'Wall-e'
        END AS ai_agent_source,
        m.is_escalated AS is_escalation,
        DATE(m.ts_created) AS dt_session_created,
        m.ts_created,
        m.ts_updated
    FROM
        datalake_chatbot.sessions as m
    LEFT JOIN
        datalake_langfuse_clean.scores s
            ON s.id_session = m.id_langfuse_session
            AND s.name = 'SessionContainsMatthewAgentEvaluator'
    LEFT JOIN
        datalake_langfuse_clean.scores s2
            ON s2.id_session = m.id_langfuse_session
            AND s2.name = 'MatthewVersionEvaluator'
    WHERE (bot = 'matthew' OR (bot = 'wall-e'))
)
SELECT
    id_session,
    id_sauron_session,
    id_external,
    id_ticket,
    id_user,
    bot,
    first_queue,
    last_queue,
    name,
    value,
    matthew_version,
    CASE
        WHEN ai_agent_source = 'Matthew in Chat' AND COALESCE(matthew_version,0) = 0 THEN 1.0
        WHEN ai_agent_source = 'Matthew in Chat' THEN COALESCE(matthew_version,0)
        WHEN ai_agent_source = 'Matthew in Whatsapp' AND COALESCE(matthew_version,0) = 0 THEN 1.5
        WHEN ai_agent_source = 'Matthew in Whatsapp' THEN COALESCE(matthew_version,0)
        WHEN ai_agent_source = 'Wall-e' THEN -1
    END AS matthew_version_host_refined,
    flag_eval_matthew_in_chat,
    ai_agent_source,
    is_escalation,
    dt_session_created,
    ts_created,
    ts_updated
FROM
    base
