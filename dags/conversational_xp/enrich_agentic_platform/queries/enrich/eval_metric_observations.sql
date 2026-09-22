WITH unpivoted AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_anonymous,
        eval_level,
        id_session,
        id_trace,
        id_chatbot,
        channel,
        session_outcome,
        topic,
        agent_declared,
        metric_key,
        metric_value,
        ts_event
    FROM
        datalake_agentic_platform.evaluations
        LATERAL VIEW explode(metrics) metrics_table AS metric_key, metric_value
    WHERE
        metrics IS NOT NULL
        AND DATE(ts_event) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
),
ranked AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_anonymous,
        eval_level,
        id_session,
        id_trace,
        id_chatbot,
        channel,
        session_outcome,
        topic,
        agent_declared,
        metric_key,
        metric_value,
        ts_event,
        ROW_NUMBER() OVER (
            PARTITION BY
                eval_level,
                CASE
                    WHEN eval_level = 'session'
                        THEN CONCAT(id_session, ':', metric_key)
                    WHEN eval_level = 'trace'
                        THEN CONCAT(
                            id_trace,
                            ':',
                            COALESCE(agent_declared, ''),
                            ':',
                            metric_key
                        )
                END
            ORDER BY
                ts_event DESC,
                id_event DESC
        ) AS row_rank
    FROM
        unpivoted
)

SELECT
    CASE
        WHEN eval_level = 'session'
            THEN CONCAT('session:', id_session, ':', metric_key)
        WHEN eval_level = 'trace'
            THEN CONCAT(
                'trace:',
                id_trace,
                ':',
                COALESCE(agent_declared, ''),
                ':',
                metric_key
            )
    END AS id_observation,
    id_event,
    id_user,
    id_person,
    id_anonymous,
    eval_level,
    id_session,
    id_trace,
    id_chatbot,
    channel,
    session_outcome,
    topic,
    agent_declared,
    metric_key,
    metric_value,
    ts_event
FROM
    ranked
WHERE
    row_rank = 1
