SELECT
    id_event,
    id_person,
    id_user,
    id_anonymous,
    ts_event,
    GET_JSON_OBJECT(event_properties, '$.tool_name') AS tool_name,
    GET_JSON_OBJECT(event_properties, '$.tool_args') AS tool_args_json,
    GET_JSON_OBJECT(event_properties, '$.tool_output') AS tool_output_json,
    TRY_CAST(
        GET_JSON_OBJECT(event_properties, '$.duration_ms') AS DOUBLE
    ) AS duration_ms,
    TRY_CAST(
        GET_JSON_OBJECT(event_properties, '$.is_error') AS BOOLEAN
    ) AS is_error,
    GET_JSON_OBJECT(event_properties, '$.error_type') AS error_type,
    GET_JSON_OBJECT(event_properties, '$.chatbot_id') AS id_chatbot,
    GET_JSON_OBJECT(event_properties, '$.session_id') AS id_session,
    GET_JSON_OBJECT(event_properties, '$.span_id') AS id_span,
    GET_JSON_OBJECT(event_properties, '$.otel_trace_id') AS id_otel_trace,
    GET_JSON_OBJECT(event_properties, '$.channel') AS channel,
    GET_JSON_OBJECT(event_properties, '$.caller_agent') AS caller_agent,
    GET_JSON_OBJECT(event_properties, '$.destination_agent') AS destination_agent
FROM
    datalake_agentic_platform.platform_events
WHERE
    event_name = 'agentic_tool_call_completed'
