SELECT
    GET_JSON_OBJECT(request, '$.request_id') AS id_request,
    trace_id AS id_trace,
    GET_JSON_OBJECT(application_payload, '$.domain_info.visit_code') AS visit_code,
    CAST(GET_JSON_OBJECT(rpc_protocol, '$.http.status_code') AS BIGINT) AS status_code,
    GET_JSON_OBJECT(application_payload, '$.tool_name') AS tool,
    GET_JSON_OBJECT(application_payload, '$.platform_info.chat_bot_name') AS host,
    timestamp AS ts_request,
    year,
    month,
    day,
    hour
FROM
    datalake_request_logging_raw.visits
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_request ORDER BY ts_request DESC) = 1
