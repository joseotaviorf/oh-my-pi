WITH istio AS (
    SELECT *
    FROM
        datalake_access_logs_clean.istio
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT 
    opa.id_decision,
    opa.id_trace,
    opa.ts_event as ts_decision,
    istio.ts_event as ts_mesh_request, 
    istio.request_traceparent, 
    istio.request_x_forwarded_for,
    istio.request_user_agent, 
    istio.request_duration_ms, 
    istio.response_flags, 
    istio.response_code,
    opa.request_source_principal, 
    opa.request_destination_principal, 
    opa.request_parameterized_path, 
    opa.request_required_roles,
    opa.request_method,
    opa.request_path,
    opa.result_http_allowed, 
    result_http_status, 
    opa.principal_user_email, 
    opa.principal_user_idp,
    opa.principal_user_issuer, 
    opa.id_principal_user_impersonated_by,  
    opa.principal_service,
    opa.principal_user_provided_roles, 
    opa.principal_service_provided_roles, 
    opa.app,
    opa.year, 
    opa.month, 
    opa.day, 
    opa.hour
FROM datalake_access_logs_clean.opa as opa
LEFT JOIN istio on opa.id_request = istio.id_request AND opa.app = istio.app
WHERE
    MAKE_DATE(opa.year, opa.month, opa.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
QUALIFY ROW_NUMBER() OVER (PARTITION BY opa.id_decision ORDER BY istio.ts_event DESC) = 1