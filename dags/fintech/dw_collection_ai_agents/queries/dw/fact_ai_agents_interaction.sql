WITH mcp AS (
    SELECT
        id_langfuse_session,
        send_proposal_count,
        flag_create_negotiation,
        flag_fetch_financial_data_error,
        n_contracts AS n_contracts_mcp,
        flag_all_empty_invoices,
        user_segment,
        negotiation_options_list,
        created_negotiation_option_key,
        created_negotiation_payment_method,
        flag_negotiation_created_missing_payment_info,
        ts_first_mcp_call,
        ts_last_mcp_call,
        CASE WHEN n_financial_context_calls > 0 THEN 1 ELSE 0 END AS flag_fetch_financial_data,
        CASE WHEN n_financial_context_calls > 0 THEN 1 ELSE 0 END AS flag_has_fetch_contracts,
        CASE WHEN n_contracts = 0 THEN 1 ELSE 0 END AS flag_handle_no_contracts,
        CASE WHEN n_contracts_negotiation_options_not_found > 0 THEN 1 ELSE 0 END AS flag_handle_segments_without_proposals,
        CASE WHEN n_annual_tax_report_calls > 0 OR n_paid_invoices_report_calls > 0 THEN 1 ELSE 0 END AS flag_get_yearly_paid_invoices_report_tool,
        CASE WHEN n_simulate_negotiation_calls > 0 THEN 1 ELSE 0 END AS flag_negotiation_proposer_tool,
        CASE WHEN n_ongoing_negotiation_calls > 0 THEN 1 ELSE 0 END AS flag_ongoing_deal_renegotiation_request_helper
    FROM
        datalake_ai_collections_quintoandar.matthew_mcp_observations
)
SELECT
    s.id_session,
    s.id_sauron_session,
    s.id_external,
    s.id_ticket,
    s.id_user,
    s.bot,
    s.first_queue,
    s.last_queue,
    s.ai_agent_source,
    s.ai_agent_source_legacy,
    s.is_matthew_in_session,
    s.flag_matthew_talked_to_user,
    s.matthew_version,
    s.flag_eval_matthew_in_chat,
    s.is_escalation,
    s.flag_session_with_trace,
    s.notif_ts_extracted,
    s.notif_text_extracted,
    s.notif_template_extracted,
    s.user_roles_raw,
    s.is_tenant,
    s.is_owner,
    s.is_owner_only,
    -- User wallet context at session date
    f.max_delay_contaminated_contract_t2,
    f.user_wallet,
    f.user_wallet_overdue_t2,
    CASE WHEN f.user_wallet_overdue_t2 > 0 THEN 'delay' ELSE 'current' END AS flag_user_delay,
    f.n_contracts,
    f.active_contracts,
    f.contracts,
    f.user_overdue_recovered_amount_t2_w_2,
    f.user_payment_w_2,
    f.array_open_invoices,
    f.array_negotiated_invoices,
    f.array_paid_invoices,
    -- Business signals unified across V2 (observation) and V3+ (matthew_mcp_observations);
    COALESCE(mcp.send_proposal_count, o.send_proposal_count, 0) AS send_proposal_count,
    COALESCE(mcp.flag_handle_segments_without_proposals, o.flag_handle_segments_without_proposals, 0) AS flag_handle_segments_without_proposals,
    COALESCE(
        CASE
            WHEN mcp.id_langfuse_session IS NULL THEN NULL
            WHEN o.confirm_negotiation_count_v3 > 0 AND mcp.flag_create_negotiation = 0 THEN 1
            ELSE 0
        END,
        o.handle_negotiation_cancelled_count,
        0
    ) AS handle_negotiation_cancelled_count,
    COALESCE(
        CASE WHEN mcp.id_langfuse_session IS NOT NULL THEN o.confirm_negotiation_count_v3 END,
        o.confirm_negotiation_count,
        0
    ) AS confirm_negotiation_count,
    COALESCE(mcp.flag_create_negotiation, o.flag_create_negotiation, 0) AS flag_create_negotiation,
    COALESCE(
        mcp.flag_fetch_financial_data,
        CASE
            WHEN o.flag_debt_retriever_tool = 1
                OR o.flag_debt_finder_tool = 1
                OR o.flag_user_debt_classifier_tool = 1
                OR o.flag_has_fetch_collections_data = 1
            THEN 1
            ELSE 0
        END,
        0
    ) AS flag_fetch_financial_data,
    COALESCE(
        mcp.flag_fetch_financial_data_error,
        CASE WHEN o.flag_has_collections_data_error = 1 OR o.flag_has_finance_fetch_error = 1 THEN 1 ELSE 0 END,
        0
    ) AS flag_fetch_financial_data_error,
    COALESCE(mcp.flag_has_fetch_contracts, o.flag_has_fetch_contracts, 0) AS flag_has_fetch_contracts,
    COALESCE(mcp.flag_handle_no_contracts, o.flag_handle_no_contracts, 0) AS flag_handle_no_contracts,
    COALESCE(mcp.flag_get_yearly_paid_invoices_report_tool, o.flag_get_yearly_paid_invoices_report_tool, 0) AS flag_get_yearly_paid_invoices_report_tool,
    COALESCE(mcp.flag_negotiation_proposer_tool, o.flag_negotiation_proposer_tool, 0) AS flag_negotiation_proposer_tool,
    COALESCE(mcp.flag_ongoing_deal_renegotiation_request_helper, o.flag_ongoing_deal_renegotiation_request_helper, 0) AS flag_ongoing_deal_renegotiation_request_helper,
    COALESCE(
        CASE
            WHEN mcp.id_langfuse_session IS NULL THEN NULL
            WHEN s.is_owner_only = 1 THEN 1
            ELSE 0
        END,
        o.flag_handle_non_tenant,
        0
    ) AS flag_handle_non_tenant,
    -- Cross-checks between agent signals and the user wallet snapshot at session date
    CASE
        WHEN mcp.flag_all_empty_invoices = 1
            AND (
                COALESCE(SIZE(f.array_open_invoices), 0) > 0
                OR COALESCE(SIZE(f.array_paid_invoices), 0) > 0
                OR COALESCE(SIZE(f.array_negotiated_invoices), 0) > 0
            )
        THEN 1
        ELSE 0
    END AS flag_empty_invoices_mismatch,
    CASE
        WHEN (o.flag_handle_no_contracts = 1 OR mcp.n_contracts_mcp = 0)
            AND f.n_contracts > 0
        THEN 1
        ELSE 0
    END AS flag_no_contracts_mismatch,
    COALESCE(o.has_prorated_rent_error, 0) AS flag_has_prorated_rent,
    COALESCE(o.flag_outbound_responsibility_helper, 0) AS flag_outbound_responsibility_helper,
    COALESCE(o.flag_authentication_helper, 0) AS flag_authentication_helper,
    payin.eval_payin_resolution,
    payin.eval_payin_failure_diagnosis,
    payin.eval_payin_frustration,
    -- LLM model, cost, latency and call-volume counters
    llm.matthew_model,
    llm.matthew_host_version,
    llm.n_agent_messages,
    llm.n_llm_calls,
    llm.total_llm_cost,
    llm.total_collections_agent_cost,
    llm.total_message_latency_sum,
    llm.collections_agent_latency_sum,
    llm.collections_agent_llm_latency_sum,
    COALESCE(llm.flag_session_had_timeout, 0) AS flag_session_had_timeout,
    COALESCE(o.is_notification_reply, 0) AS is_notification_reply,
    COALESCE(s.flag_escalation_attempted, 0) AS flag_escalation_attempted,
    s.matthew_declared_escalation_reason,
    s.matthew_declared_escalation_queue,
    o.ts_first_observation,
    o.ts_last_observation,
    -- V3+ MCP signals (NULL for V2 sessions)
    mcp.n_contracts_mcp,
    mcp.flag_all_empty_invoices AS flag_all_empty_invoices_mcp,
    mcp.user_segment,
    mcp.negotiation_options_list,
    mcp.created_negotiation_option_key,
    mcp.created_negotiation_payment_method,
    mcp.flag_negotiation_created_missing_payment_info,
    mcp.ts_first_mcp_call,
    mcp.ts_last_mcp_call,
    -- Agglutinated conversation for downstream LLM analysis
    msg.full_conversation,
    s.dt_session_created,
    s.ts_created,
    s.ts_updated
FROM
    datalake_ai_collections_quintoandar.sessions AS s
LEFT JOIN
    dw_collection_ai_agents.fact_user_wallet_timeline AS f
        ON f.sk_user = s.id_user
        AND f.dt_reference = s.dt_session_created
LEFT JOIN
    datalake_ai_collections_quintoandar.observation AS o
        ON o.id_langfuse_session = s.id_external
LEFT JOIN
    mcp
        ON mcp.id_langfuse_session = s.id_external
LEFT JOIN
    datalake_ai_collections_quintoandar.messages AS msg
        ON msg.id_external = s.id_external
LEFT JOIN
    datalake_ai_collections_quintoandar.matthew_llm_metrics AS llm
        ON llm.id_langfuse_session = s.id_external
LEFT JOIN
    datalake_ai_collections_quintoandar.matthew_payin_evals AS payin
        ON payin.id_langfuse_session = s.id_external
WHERE s.flag_session_with_trace
