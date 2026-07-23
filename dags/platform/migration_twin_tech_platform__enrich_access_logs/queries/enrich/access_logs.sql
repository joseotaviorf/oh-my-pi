WITH opa_filtered AS (
    SELECT
        id_decision,
        id_trace,
        ts_event,
        id_request,
        request_real_ip,
        request_source_principal,
        request_destination_principal,
        request_parameterized_path,
        request_required_roles,
        request_method,
        request_path,
        result_http_allowed,
        result_decision,
        result_decision_reasons,
        result_http_status,
        principal_user_idp,
        principal_user_provided_roles,
        principal_service_provided_roles,
        app,
        year,
        month,
        day,
        hour
    FROM
        datalake_access_logs_clean.opa
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
istio_filtered AS (
    SELECT
        id_request,
        ts_event,
        request_traceparent,
        request_x_forwarded_for,
        request_user_agent,
        request_duration_ms,
        response_flags,
        response_code,
        principal_user_email,
        id_principal_user,
        uuid_person_principal_user,
        principal_user_issuer,
        principal_service,
        id_principal_user_impersonated_by,
        principal_identities_json,
        pod_name,
        app,
        year,
        month,
        day,
        hour
    FROM
        datalake_access_logs_clean.istio
    WHERE
         MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_request, app ORDER BY ts_event DESC) = 1
)
SELECT
    opa.id_decision,
    opa.id_trace,
    opa.ts_event as ts_decision,
    istio.ts_event as ts_mesh_request,
    istio.request_traceparent,
    istio.request_x_forwarded_for,
    opa.request_real_ip,
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
    opa.result_decision,
    opa.result_decision_reasons,
    opa.result_http_status,
    istio.principal_user_email,
    CAST(istio.id_principal_user AS STRING) AS id_main_principal_user,
    istio.uuid_person_principal_user,
    opa.principal_user_idp,
    istio.principal_user_issuer,
    istio.id_principal_user_impersonated_by,
    istio.principal_service,
    istio.principal_identities_json,
    opa.principal_user_provided_roles,
    opa.principal_service_provided_roles,
    opa.app,
    istio.pod_name,
    opa.year,
    opa.month,
    opa.day,
    opa.hour
FROM
    opa_filtered as opa
LEFT JOIN
    istio_filtered as istio
    ON opa.id_request = istio.id_request
    AND opa.app = istio.app
