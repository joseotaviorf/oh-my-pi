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
    f.user_wallet_overdue_t2,
    CASE WHEN f.user_wallet_overdue_t2 > 0 THEN 'delay' ELSE 'current' END AS flag_user_delay,
    f.n_contracts,
    f.active_contracts,
    f.contracts,
    f.array_open_invoices,
    -- Observation flags / counts (coalesced to 0 when no observations recorded)
    COALESCE(o.flag_ask_user_preferences, 0) AS flag_ask_user_preferences,
    COALESCE(o.send_proposal_count, 0) AS send_proposal_count,
    COALESCE(o.flag_handle_segments_without_proposals, 0) AS flag_handle_segments_without_proposals,
    COALESCE(o.handle_negotiation_cancelled_count, 0) AS handle_negotiation_cancelled_count,
    COALESCE(o.confirm_negotiation_count, 0) AS confirm_negotiation_count,
    COALESCE(o.flag_create_negotiation, 0) AS flag_create_negotiation,
    COALESCE(o.flag_collectionsinput_agent, 0) AS flag_collectionsinput_agent,
    COALESCE(o.is_notification_reply, 0) AS is_notification_reply,
    COALESCE(o.flag_has_collections_data_error, 0) AS flag_has_collections_data_error,
    COALESCE(o.flag_has_fetch_collections_data, 0) AS flag_has_fetch_collections_data,
    COALESCE(o.flag_handle_no_contracts, 0) AS flag_handle_no_contracts,
    COALESCE(o.flag_has_fetch_contracts, 0) AS flag_has_fetch_contracts,
    -- Matthew tools invoked
    COALESCE(o.flag_payment_allegation_tool, 0) AS flag_payment_allegation_tool,
    COALESCE(o.flag_debt_retriever_tool, 0) AS flag_debt_retriever_tool,
    COALESCE(o.flag_user_debt_classifier_tool, 0) AS flag_user_debt_classifier_tool,
    COALESCE(o.flag_debt_finder_tool, 0) AS flag_debt_finder_tool,
    COALESCE(o.flag_get_yearly_paid_invoices_report_tool, 0) AS flag_get_yearly_paid_invoices_report_tool,
    COALESCE(o.flag_negotiation_proposer_tool, 0) AS flag_negotiation_proposer_tool,
    -- Helpers and edge-case handlers
    COALESCE(o.flag_debt_summary_display_helper, 0) AS flag_debt_summary_display_helper,
    COALESCE(o.flag_original_invoice_values_disagreement_helper, 0) AS flag_original_invoice_values_disagreement_helper,
    COALESCE(o.flag_ongoing_deal_renegotiation_request_helper, 0) AS flag_ongoing_deal_renegotiation_request_helper,
    COALESCE(o.flag_handle_non_tenant, 0) AS flag_handle_non_tenant,
    o.ts_first_observation,
    o.ts_last_observation,
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
    datalake_ai_collections_quintoandar.messages AS msg
        ON msg.id_sauron_session = s.id_sauron_session
WHERE s.flag_session_with_trace
