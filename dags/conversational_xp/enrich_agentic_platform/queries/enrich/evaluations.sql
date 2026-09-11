SELECT
    id_event,
    id_person,
    id_user,
    ts_event,
    CASE
        WHEN event_name = 'agentic_platform_session_evaluation' THEN 'session'
        WHEN event_name = 'agentic_platform_trace_evaluation' THEN 'trace'
        ELSE RAISE_ERROR(
            CONCAT(
                'Unknown agentic platform evaluation event ',
                COALESCE(event_name, '<null>'),
                ' for id_event ',
                id_event
            )
        )
    END AS eval_level,
    GET_JSON_OBJECT(event_properties, '$.session_id') AS id_session,
    GET_JSON_OBJECT(event_properties, '$.trace_id') AS id_trace,
    GET_JSON_OBJECT(event_properties, '$.chatbot') AS id_chatbot,
    GET_JSON_OBJECT(event_properties, '$.channel') AS channel,
    GET_JSON_OBJECT(event_properties, '$.session_outcome') AS session_outcome,
    GET_JSON_OBJECT(event_properties, '$.topic') AS topic,
    GET_JSON_OBJECT(event_properties, '$.agent') AS agent_declared,
    FROM_JSON(
        GET_JSON_OBJECT(event_properties, '$.metrics'),
        'map<string,double>'
    ) AS metrics
FROM
    datalake_agentic_platform.platform_events
WHERE
    event_name RLIKE '^agentic_platform_'
