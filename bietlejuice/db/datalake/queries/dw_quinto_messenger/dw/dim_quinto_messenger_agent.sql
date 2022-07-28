WITH agents AS (
    SELECT
        id_agent,
        agent_email
    FROM datalake_quinto_messenger.task
    GROUP BY 1,2
),
last_task_event_updates AS (
    SELECT
        agent_email,
        MAX(ts_updated) AS ts_last_updated
    FROM datalake_quinto_messenger.task_event
    GROUP BY 1
)
SELECT
    a.id_agent AS sk_quinto_messenger_agent,
    e.agent_full_name AS name,
    e.agent_email AS email,
    e.agent_location AS location,
    e.agent_skills AS skills,
    MAX(le.ts_last_updated) AS ts_updated,
    NOW() AS ts_load
FROM datalake_quinto_messenger.task_event e
INNER JOIN last_task_event_updates le
    ON e.agent_email = e.agent_email
    AND e.ts_updated = le.ts_last_updated
INNER JOIN agents a
    ON e.agent_email = a.agent_email
GROUP BY 1,2,3,4,5
