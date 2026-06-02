-- Read the full 3-day history for all sessions once. A window flag marks sessions
-- that had at least one call in the current load window; the outer WHERE then keeps
-- only those, so cross-day sessions are always re-aggregated from their earliest log.
WITH base AS (
    SELECT
        mtl.id_langfuse_session,
        mtl.id_request,
        mtl.id_trace,
        mtl.id_user,
        mtl.uuid_person_mcp,
        mtl.id_contract_mcp,
        mtl.id_contract_call,
        mtl.mcp_tool_name,
        mtl.mcp_option_key,
        mtl.mcp_payment_method,
        mtl.call_function_name,
        mtl.call_outcome,
        mtl.call_response,
        mtl.call_http_status,
        mtl.is_mcp_success,
        mtl.is_call_success,
        mtl.ts_request,
        MAX(
            CASE
                WHEN mtl.ts_request >= TIMESTAMP('{load_start_date}')
                THEN 1
                ELSE 0
            END
        ) OVER (PARTITION BY mtl.id_langfuse_session) AS is_touched_in_window
    FROM
        datalake_ai_collections_quintoandar.mcp_tool_logs AS mtl
    WHERE
        MAKE_DATE(mtl.year, mtl.month, mtl.day) >= DATE('{load_start_date}') - INTERVAL 3 DAY
        AND mtl.id_langfuse_session IS NOT NULL
)
SELECT
    b.id_langfuse_session,
    -- Group 1: Identity (first non-null per session)
    MAX(b.id_user) AS id_user,
    MAX(b.uuid_person_mcp) AS uuid_person_mcp,
    -- Group 2: Tool invocation counts (COUNT DISTINCT id_request per tool)
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_financial_context_v1' THEN b.id_request END) AS n_financial_context_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_financial_context_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_financial_context_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_debt_breakdown_v1' THEN b.id_request END) AS n_debt_breakdown_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_debt_breakdown_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_debt_breakdown_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_negotiation_options_v1' THEN b.id_request END) AS n_negotiation_options_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_negotiation_options_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_negotiation_options_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'simulate_negotiation_v1' THEN b.id_request END) AS n_simulate_negotiation_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'simulate_negotiation_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_simulate_negotiation_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'create_negotiation_v1' THEN b.id_request END) AS n_create_negotiation_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'create_negotiation_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_create_negotiation_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_ongoing_negotiation_information_v1' THEN b.id_request END) AS n_ongoing_negotiation_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_ongoing_negotiation_information_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_ongoing_negotiation_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_annual_tax_report_v1' THEN b.id_request END) AS n_annual_tax_report_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_annual_tax_report_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_annual_tax_report_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_paid_invoices_annual_report_v1' THEN b.id_request END) AS n_paid_invoices_report_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_paid_invoices_annual_report_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_paid_invoices_report_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_last_paid_invoices_v1' THEN b.id_request END) AS n_last_paid_invoices_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_last_paid_invoices_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_last_paid_invoices_errors,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_original_invoices_by_status_v1' THEN b.id_request END) AS n_original_invoices_calls,
    COUNT(DISTINCT CASE WHEN b.mcp_tool_name = 'get_original_invoices_by_status_v1' AND b.is_mcp_success = false THEN b.id_request END) AS n_original_invoices_errors,
    COUNT(DISTINCT CASE WHEN b.is_mcp_success = false THEN b.id_request END) AS n_mcp_tool_errors,
    -- Group 3: Financial context signals (from get_financial_context_v1 downstream calls)
    MAX(
        CASE
            WHEN b.call_function_name = 'GetContracts'
                AND b.is_call_success = true
            THEN SIZE(FROM_JSON(b.call_response, 'ARRAY<BIGINT>'))
        END
    ) AS n_contracts,
    CASE
        WHEN COUNT(
            CASE
                WHEN b.call_function_name IN ('GetInvoicesForContract', 'GetDetailedBills')
                THEN 1
            END
        ) = 0
            THEN NULL
        WHEN COUNT(
            CASE
                WHEN b.call_function_name IN ('GetInvoicesForContract', 'GetDetailedBills')
                    AND (b.call_response IS NULL OR b.call_response != 'empty')
                THEN 1
            END
        ) = 0
            THEN TRUE
        ELSE FALSE
    END AS all_empty_invoices,
    MAX(
        CASE
            WHEN b.call_function_name = 'GetCustomerSegment'
                AND b.is_call_success = true
            THEN b.call_response
        END
    ) AS user_segment,
    -- Group 4: Contract-level aggregates
    COUNT(
        DISTINCT CASE
            WHEN b.call_function_name = 'GetDebtBreakdown'
                AND b.call_http_status = 422
            THEN b.id_contract_call
        END
    ) AS n_contracts_distribution_error,
    COUNT(
        DISTINCT CASE
            WHEN b.call_function_name = 'GetOngoingNegotiation'
                AND b.call_outcome = 'success'
                AND (b.call_response IS NULL OR b.call_response != 'empty')
            THEN b.id_contract_call
        END
    ) AS n_contracts_active_negotiation,
    COUNT(
        DISTINCT CASE
            WHEN b.call_function_name = 'GetNegotiationOptions'
                AND b.call_response LIKE 'empty:%'
            THEN b.id_contract_mcp
        END
    ) AS n_contracts_negotiation_options_not_found,
    COUNT(
        DISTINCT CASE
            WHEN b.call_function_name = 'GetNegotiationOptions'
                AND b.call_response = 'empty:NOT_FOUND'
            THEN b.id_contract_mcp
        END
    ) AS n_contracts_negotiation_not_found_person_not_found,
    COUNT(
        DISTINCT CASE
            WHEN b.call_function_name = 'GetNegotiationOptions'
                AND b.call_response = 'empty:NO_OPTIONS_FOR_AUDIENCE'
            THEN b.id_contract_mcp
        END
    ) AS n_contracts_negotiation_not_found_options_empty,
    COUNT(
        DISTINCT CASE
            WHEN b.call_function_name = 'GetNegotiationOptions'
                AND b.call_response = 'empty:ONGOING_NEGOTIATION'
            THEN b.id_contract_mcp
        END
    ) AS n_contracts_negotiation_not_found_ongoing_negotiation,
    -- Group 5: Negotiation outcome signals
    MAX(
        CASE
            WHEN b.call_function_name = 'GetNegotiationOptions'
                AND b.is_call_success = true
                AND b.call_response NOT LIKE 'empty:%'
            THEN b.call_response
        END
    ) AS negotiation_options_list,
    COUNT(
        DISTINCT CASE
            WHEN b.mcp_tool_name = 'simulate_negotiation_v1'
                AND b.is_mcp_success = true
            THEN b.id_trace
        END
    ) AS send_proposal_count,
    MAX(
        CASE
            WHEN b.mcp_tool_name = 'create_negotiation_v1'
                AND b.is_mcp_success = true
            THEN 1
            ELSE 0
        END
    ) = 1 AS is_negotiation_created,
    MAX(
        CASE
            WHEN b.mcp_tool_name = 'create_negotiation_v1'
                AND b.is_mcp_success = true
            THEN b.mcp_option_key
        END
    ) AS created_negotiation_option_key,
    MAX(
        CASE
            WHEN b.mcp_tool_name = 'create_negotiation_v1'
                AND b.is_mcp_success = true
            THEN b.mcp_payment_method
        END
    ) AS created_negotiation_payment_method,
    (
        MAX(
            CASE
                WHEN b.mcp_tool_name = 'simulate_negotiation_v1'
                    AND b.is_mcp_success = true
                THEN 1
                ELSE 0
            END
        ) = 1
        AND MAX(
            CASE
                WHEN b.mcp_tool_name = 'create_negotiation_v1'
                    AND b.is_mcp_success = true
                THEN 1
                ELSE 0
            END
        ) = 0
    ) AS is_negotiation_flow_partial,
    (
        MAX(
            CASE
                WHEN b.mcp_tool_name = 'create_negotiation_v1'
                    AND b.is_mcp_success = true
                THEN 1
                ELSE 0
            END
        ) = 1
        AND COUNT(
            DISTINCT CASE
                WHEN b.call_function_name = 'GetOngoingNegotiation'
                    AND b.call_outcome = 'success'
                    AND (b.call_response IS NULL OR b.call_response != 'empty')
                THEN b.id_contract_call
            END
        ) = 0
    ) AS is_negotiation_created_missing_payment_info,
    -- Group 6: Temporal
    MIN(b.ts_request) AS ts_first_mcp_call,
    MAX(b.ts_request) AS ts_last_mcp_call,
    YEAR(MAX(b.ts_request)) AS year,
    MONTH(MAX(b.ts_request)) AS month,
    DAYOFMONTH(MAX(b.ts_request)) AS day
FROM
    base AS b
WHERE
    b.is_touched_in_window = 1
GROUP BY
    b.id_langfuse_session
