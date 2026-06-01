SELECT
    GET_JSON_OBJECT(request, '$.request_id') AS id_request,
    event_id AS id_event,
    experiment_ids AS id_experiment,
    trace_id AS id_trace,
    tracking_ids AS id_tracking,
    TRY_CAST(GET_JSON_OBJECT(auth, '$.user_id.legacy_id') AS BIGINT) AS id_user,
    GET_JSON_OBJECT(auth, '$.user_id.person_id') AS uuid_person,
    application_name,
    GET_JSON_OBJECT(application_payload, '$.tool_name') AS tool_name,
    TRY_CAST(GET_JSON_OBJECT(rpc_protocol, '$.http.status_code') AS INT) AS http_status_code,
    application_payload,
    auth,
    headers,
    message_key,
    `offset`,
    `partition`,
    request,
    rpc_protocol,
    s3_key_prefix,
    `source`,
    source_type,
    topic,
    `timestamp` AS ts_request,
    year,
    month,
    day,
    hour
FROM
    datalake_request_logging_raw.collections
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_request ORDER BY ts_request DESC) = 1
