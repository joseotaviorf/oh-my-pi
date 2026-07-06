WITH visits_ranked AS (
    SELECT
        GET_JSON_OBJECT(request, '$.request_id') AS id_request,
        trace_id AS id_trace,
        GET_JSON_OBJECT(application_payload, '$.domain_info.visit_code') AS visit_code,
        CAST(GET_JSON_OBJECT(rpc_protocol, '$.http.status_code') AS BIGINT) AS status_code,
        GET_JSON_OBJECT(application_payload, '$.tool_name') AS tool,
        GET_JSON_OBJECT(application_payload, '$.platform_info.chat_bot_name') AS host,
        GET_JSON_OBJECT(application_payload, '$.platform_info.origin_chat_app') AS channel,
        GET_JSON_OBJECT(application_payload, '$.domain_info.actor_role') AS actor_role,
        timestamp AS ts_request,
        year,
        month,
        day,
        hour,
        ROW_NUMBER() OVER (PARTITION BY GET_JSON_OBJECT(request, '$.request_id') ORDER BY timestamp DESC) AS rn
    FROM
        datalake_request_logging_raw.visits
)
SELECT
    id_request,
    id_trace,
    visit_code,
    status_code,
    tool,
    host,
    channel,
    actor_role,
    ts_request,
    year,
    month,
    day,
    hour
FROM
    visits_ranked
WHERE
    rn = 1
