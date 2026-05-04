WITH touched_sessions AS (
    SELECT DISTINCT
        id_sauron_session
    FROM
        datalake_chatbot.messages
    WHERE
        ts_created >= '{load_start_date}'
        AND id_sauron_session IS NOT NULL
),
matthew_sessions AS (
    SELECT
        s.id_sauron_session,
        s.id_external
    FROM
        datalake_ai_collections_quintoandar.sessions AS s
    INNER JOIN
        touched_sessions AS ts
            ON ts.id_sauron_session = s.id_sauron_session
    WHERE s.flag_session_with_trace and s.ai_agent_source in ('Matthew in Chat', 'Matthew in Whatsapp')
),
messages_as_struct AS (
    SELECT
        m.id_sauron_session,
        ms.id_external,
        m.ts_created,
        STRUCT(
            m.ts_created,
            CONCAT(
                CAST(
                    CASE
                        WHEN m.role = 'HUMAN' THEN CONCAT('user_', COALESCE(CAST(m.id_user AS STRING), 'unknown'))
                        ELSE m.role
                    END AS STRING
                ),
                ': ',
                m.message
            )
        ) AS message_data
    FROM
        datalake_chatbot.messages AS m
    INNER JOIN
        matthew_sessions AS ms
            ON ms.id_sauron_session = m.id_sauron_session
    WHERE
        m.message IS NOT NULL
)
SELECT
    id_sauron_session,
    id_external,
    MIN(ts_created) AS ts_session_start,
    MAX(ts_created) AS ts_session_end,
    ARRAY_JOIN(
        TRANSFORM(
            ARRAY_SORT(ARRAY_AGG(message_data)),
            element -> element.col2
        ),
        '\n'
    ) AS full_conversation,
    YEAR(MAX(ts_created)) AS year,
    MONTH(MAX(ts_created)) AS month,
    DAYOFMONTH(MAX(ts_created)) AS day
FROM
    messages_as_struct
GROUP BY
    id_sauron_session,
    id_external
