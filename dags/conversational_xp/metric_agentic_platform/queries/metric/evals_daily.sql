SELECT
    DATE(ts_event) AS dt,
    eval_level AS grain,
    COALESCE(id_chatbot, '__UNKNOWN__') AS id_chatbot,
    COALESCE(channel, '__UNKNOWN__') AS channel,
    COALESCE(session_outcome, '__UNKNOWN__') AS session_outcome,
    COALESCE(topic, '__UNKNOWN__') AS topic,
    COALESCE(agent_declared, '__UNKNOWN__') AS agent_declared,
    metric_key,
    COUNT(*) AS cnt_observations,
    SUM(
        CASE
            WHEN metric_value >= 1 THEN 1
            ELSE 0
        END
    ) AS cnt_positive,
    SUM(metric_value) AS sum_value
FROM
    datalake_agentic_platform.eval_metric_observations
WHERE
    DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY
    DATE(ts_event),
    eval_level,
    COALESCE(id_chatbot, '__UNKNOWN__'),
    COALESCE(channel, '__UNKNOWN__'),
    COALESCE(session_outcome, '__UNKNOWN__'),
    COALESCE(topic, '__UNKNOWN__'),
    COALESCE(agent_declared, '__UNKNOWN__'),
    metric_key
