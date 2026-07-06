WITH entryaccess_ranked AS (
    SELECT
        GET_JSON_OBJECT(request, '$.request_id') AS id_request,
        trace_id AS id_trace,
        GET_JSON_OBJECT(application_payload, '$.domain_info.house_id') AS id_house,
        CAST(GET_JSON_OBJECT(rpc_protocol, '$.http.status_code') AS BIGINT) AS status_code,
        GET_JSON_OBJECT(application_payload, '$.tool_name') AS tool,
        GET_JSON_OBJECT(application_payload, '$.platform_info.chat_bot_name') AS host,
        GET_JSON_OBJECT(application_payload, '$.platform_info.origin_chat_app') AS channel,
        timestamp AS ts_request,
        year,
        month,
        day,
        hour,
        ROW_NUMBER() OVER (PARTITION BY GET_JSON_OBJECT(request, '$.request_id') ORDER BY timestamp DESC) AS rn
    FROM
        datalake_request_logging_raw.entryaccess
)
SELECT
    id_request,
    id_trace,
    id_house,
    status_code,
    tool,
    host,
    channel,
    ts_request,
    year,
    month,
    day,
    hour
FROM
    entryaccess_ranked
WHERE
    rn = 1
