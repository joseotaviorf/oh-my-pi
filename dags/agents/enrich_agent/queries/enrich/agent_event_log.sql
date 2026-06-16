WITH agent_updated AS (
    SELECT DISTINCT
        id_agent
    FROM
        datalake_ebdb_clean.agent_event_log
    WHERE
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    ael.id AS id_event_log,
    ael.id_agent,
    ael.id_capability,
    ael.author_identifier AS id_author_user,
    ael.author_type,
    ael.author_role,
    ael.channel,
    ael.reason,
    ael.on_behalf_of_role,
    IF(ael.id_capability IS NULL, 'AGENT', 'CAPABILITY') AS event_level,
    c.type AS capability_type,
    ael.event_type,
    ael.ts_created AS ts_started,
    LEAD(ael.ts_created) OVER(PARTITION BY ael.id_agent, ael.id_capability ORDER BY ael.ts_created) AS ts_ended,
    ael.ts_updated,
    YEAR(ael.ts_updated) AS year,
    MONTH(ael.ts_updated) AS month,
    DAY(ael.ts_updated) AS day
FROM
    agent_updated AS au
JOIN
    datalake_ebdb_clean.agent_event_log AS ael
        ON au.id_agent = ael.id_agent
LEFT JOIN
    datalake_ebdb_clean.capability AS c
        ON ael.id_capability = c.id
