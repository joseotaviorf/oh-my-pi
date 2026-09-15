WITH collections AS (
    SELECT
        c.id_request,
        c.id_trace,
        c.id_user,
        c.uuid_person AS uuid_person_mcp,
        c.tool_name AS mcp_tool_name,
        c.http_status_code AS mcp_http_status_code,
        TRY_CAST(GET_JSON_OBJECT(c.application_payload, '$.domain_info.contract_id') AS BIGINT) AS id_contract_mcp,
        TRY_CAST(GET_JSON_OBJECT(c.request, '$.duration_ms') AS INT) AS mcp_duration_ms,
        GET_JSON_OBJECT(c.application_payload, '$.domain_info.option_key') AS mcp_option_key,
        GET_JSON_OBJECT(c.application_payload, '$.domain_info.payment_method') AS mcp_payment_method,
        GET_JSON_OBJECT(c.application_payload, '$.domain_info.calls') AS calls_json_str,
        FROM_JSON(
            GET_JSON_OBJECT(c.application_payload, '$.domain_info.calls'),
            'ARRAY<STRUCT<client:STRING, function:STRING, outcome:STRING, http_status:INT, reason:STRING, contract_id:LONG, order_id:STRING, house_ids:ARRAY<LONG>, attempt:INT, invoice_preview_dispatch:STRING>>'
        ) AS calls_array,
        c.ts_request,
        ROW_NUMBER() OVER (
            PARTITION BY c.id_trace, LOWER(c.tool_name)
            ORDER BY c.ts_request ASC, c.id_request ASC
        ) AS mcp_seq
    FROM
        datalake_request_logging_clean.collections AS c
    WHERE
        MAKE_DATE(c.year, c.month, c.day) >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND c.ts_request >= TIMESTAMP('{load_start_date}') - INTERVAL 1 DAY
        AND c.tool_name IS NOT NULL
        AND c.id_event = CONCAT('MCP_TOOL_', c.tool_name)
),
tool_observations AS (
    SELECT
        obs.id_trace,
        LOWER(obs.name) AS obs_tool_name_lower,
        obs.input AS obs_input,
        obs.output AS obs_output,
        ROW_NUMBER() OVER (
            PARTITION BY obs.id_trace, LOWER(obs.name)
            ORDER BY obs.ts_started ASC, obs.id_observation ASC
        ) AS obs_seq
    FROM
        datalake_langfuse_clean.observations AS obs
    WHERE
        obs.ts_started >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
        AND obs.type = 'TOOL'
        AND NOT (obs.level = 'ERROR' AND obs.output IS NULL)
        AND LOWER(obs.name) IN (
            'get_financial_context_v1',
            'get_annual_tax_report_v1',
            'get_debt_breakdown_v1',
            'get_negotiation_options_v1',
            'get_ongoing_negotiation_information_v1',
            'get_last_paid_invoices_v1',
            'simulate_negotiation_v1',
            'create_negotiation_v1',
            'get_original_invoices_by_status_v1',
            'send_original_invoice_boleto_pix_email',
            'get_next_invoice_preview_v1'
        )
),
mcp_with_obs AS (
    SELECT
        m.id_request,
        m.id_trace,
        trc.id_session AS id_langfuse_session,
        trc.environment,
        m.id_user,
        m.uuid_person_mcp,
        m.mcp_tool_name,
        m.mcp_http_status_code,
        m.id_contract_mcp,
        m.mcp_duration_ms,
        m.mcp_option_key,
        m.mcp_payment_method,
        m.calls_array,
        m.calls_json_str,
        m.ts_request,
        (m.mcp_http_status_code BETWEEN 200 AND 299) AS is_mcp_success,
        t.obs_input AS mcp_input,
        CASE
            WHEN m.mcp_http_status_code IS NULL THEN NULL
            WHEN m.mcp_http_status_code BETWEEN 200 AND 299 THEN NULL
            ELSE CAST(t.obs_output AS STRING)
        END AS mcp_tool_error_message
    FROM
        collections AS m
    LEFT JOIN
        tool_observations AS t
            ON t.id_trace = m.id_trace
            AND t.obs_tool_name_lower = LOWER(m.mcp_tool_name)
            AND t.obs_seq = m.mcp_seq
    LEFT JOIN
        datalake_langfuse_clean.traces AS trc
            ON trc.id_trace = m.id_trace
)
SELECT
    p.id_request,
    p.id_trace,
    p.id_langfuse_session,
    p.id_user,
    p.id_contract_mcp,
    CAST(call.contract_id AS BIGINT) AS id_contract_call,
    p.uuid_person_mcp,
    p.environment,
    p.mcp_tool_name,
    p.mcp_option_key,
    p.mcp_payment_method,
    call.client AS call_client,
    call.function AS call_function_name,
    call.outcome AS call_outcome,
    call.reason AS call_reason,
    call.order_id AS call_order_id,
    call.attempt AS call_attempt,
    call.invoice_preview_dispatch AS call_invoice_preview_dispatch,
    pos AS call_index,
    p.mcp_input,
    p.mcp_tool_error_message,
    GET_JSON_OBJECT(p.calls_json_str, CONCAT('$[', pos, '].response')) AS call_response,
    p.mcp_duration_ms,
    p.mcp_http_status_code,
    call.http_status AS call_http_status,
    p.is_mcp_success,
    (call.outcome = 'success') AS is_call_success,
    p.ts_request,
    call.house_ids AS call_house_ids,
    CASE
        WHEN call.function = 'GetInvoicePreview'
        THEN FROM_JSON(
            GET_JSON_OBJECT(p.calls_json_str, CONCAT('$[', pos, '].response')),
            'ARRAY<STRING>'
        )
    END AS call_invoice_preview_entries,
    CASE
        WHEN call.function = 'GetContractBillingFacts'
        THEN TRY_CAST(
            GET_JSON_OBJECT(
                GET_JSON_OBJECT(p.calls_json_str, CONCAT('$[', pos, '].response')),
                '$.hasRentalGuarantee'
            ) AS BOOLEAN
        )
    END AS call_has_rental_guarantee,
    CASE
        WHEN call.function = 'GetContractBillingFacts'
        THEN TRY_CAST(
            GET_JSON_OBJECT(
                GET_JSON_OBJECT(p.calls_json_str, CONCAT('$[', pos, '].response')),
                '$.occupancyStartDate'
            ) AS DATE
        )
    END AS call_dt_occupancy_started,
    CASE
        WHEN call.function = 'GetContractBillingFacts'
        THEN GET_JSON_OBJECT(
            GET_JSON_OBJECT(p.calls_json_str, CONCAT('$[', pos, '].response')),
            '$.condominiumPayer'
        )
    END AS call_condominium_payer,
    TO_JSON(call) AS call_payload_json,
    YEAR(p.ts_request) AS year,
    MONTH(p.ts_request) AS month,
    DAYOFMONTH(p.ts_request) AS day
FROM
    mcp_with_obs AS p
LATERAL VIEW POSEXPLODE(p.calls_array) AS pos, call
WHERE
    p.id_langfuse_session IS NOT NULL
    AND p.environment = 'prod'
