SELECT
    id,
    http_method,
    endpoint_path,
    certificate_id AS id_certificate,
    flow_type,
    request_body,
    response_status_code,
    response_body,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(request_timestamp) AS ts_request,
    TIMESTAMP(response_timestamp) AS ts_response,
    year,
    month,
    day
FROM
    datalake_betopera_raw.api_audit_log
