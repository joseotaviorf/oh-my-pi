SELECT
    trc.id_session AS id_langfuse_session,
    -- Group 1: Negotiation flow signals
    MAX(CASE WHEN LOWER(obs.name) = 'ask_user_preferences' THEN 1 ELSE 0 END) AS flag_ask_user_preferences,
    SUM(CASE WHEN LOWER(obs.name) = 'send_proposal' THEN 1 ELSE 0 END) AS send_proposal_count,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_segments_without_proposals' THEN 1 ELSE 0 END) AS flag_handle_segments_without_proposals,
    SUM(CASE WHEN LOWER(obs.name) = 'handle_negotiation_cancelled' THEN 1 ELSE 0 END) AS handle_negotiation_cancelled_count,
    SUM(CASE WHEN LOWER(obs.name) = 'confirm_negotiation' THEN 1 ELSE 0 END) AS confirm_negotiation_count,
    MAX(CASE WHEN LOWER(obs.name) = 'create_negotiation' THEN 1 ELSE 0 END) AS flag_create_negotiation,
    -- Group 2: Matthew technical-state signals
    MAX(CASE WHEN LOWER(obs.name) = 'collectionsinput' THEN 1 ELSE 0 END) AS flag_collectionsinput_agent,
    MAX(CASE WHEN LOWER(obs.name) = 'outbound_payload_from_dto' THEN 1 ELSE 0 END) AS is_notification_reply,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_collections_data_error' AND obs.type IN ('CHAIN', 'TOOL') THEN 1 ELSE 0 END) AS flag_has_collections_data_error,
    MAX(CASE WHEN LOWER(obs.name) = 'fetch_collections_data' AND obs.type IN ('CHAIN', 'TOOL') THEN 1 ELSE 0 END) AS flag_has_fetch_collections_data,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_no_contracts' AND obs.type IN ('CHAIN', 'TOOL') THEN 1 ELSE 0 END) AS flag_handle_no_contracts,
    MAX(CASE WHEN LOWER(obs.name) = 'fetch_contracts' AND obs.type IN ('CHAIN', 'TOOL') THEN 1 ELSE 0 END) AS flag_has_fetch_contracts,
    -- Group 3: Matthew tools invoked
    MAX(CASE WHEN LOWER(obs.name) = 'paymentallegationtool' THEN 1 ELSE 0 END) AS flag_payment_allegation_tool,
    MAX(CASE WHEN LOWER(obs.name) = 'debtretrievertool' THEN 1 ELSE 0 END) AS flag_debt_retriever_tool,
    MAX(CASE WHEN LOWER(obs.name) = 'userdebtclassifiertool' THEN 1 ELSE 0 END) AS flag_user_debt_classifier_tool,
    MAX(CASE WHEN LOWER(obs.name) = 'debtfindertool' THEN 1 ELSE 0 END) AS flag_debt_finder_tool,
    MAX(CASE WHEN LOWER(obs.name) = 'get_yearly_paid_invoices_report_tool' THEN 1 ELSE 0 END) AS flag_get_yearly_paid_invoices_report_tool,
    MAX(CASE WHEN LOWER(obs.name) = 'negotiationproposertool' THEN 1 ELSE 0 END) AS flag_negotiation_proposer_tool,
    -- Group 4: Helpers and edge-case handlers
    MAX(CASE WHEN LOWER(obs.name) = 'debt_summary_display_helper' THEN 1 ELSE 0 END) AS flag_debt_summary_display_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'original_invoice_values_disagreement_helper' THEN 1 ELSE 0 END) AS flag_original_invoice_values_disagreement_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'ongoing_deal_renegotiation_request_helper' THEN 1 ELSE 0 END) AS flag_ongoing_deal_renegotiation_request_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_non_tenant' THEN 1 ELSE 0 END) AS flag_handle_non_tenant,
    -- Temporal aggregates (over the tracked observations only)
    MIN(obs.ts_started) AS ts_first_observation,
    MAX(obs.ts_ended) AS ts_last_observation,
    YEAR(MAX(COALESCE(obs.ts_ended, obs.ts_started))) AS year,
    MONTH(MAX(COALESCE(obs.ts_ended, obs.ts_started))) AS month,
    DAYOFMONTH(MAX(COALESCE(obs.ts_ended, obs.ts_started))) AS day
FROM
    datalake_langfuse_clean.observations AS obs
INNER JOIN
    datalake_langfuse_clean.traces AS trc
        ON trc.id_trace = obs.id_trace
INNER JOIN
    datalake_chatbot.sessions AS cs
        ON cs.id_langfuse_session = trc.id_session
        AND cs.bot IN ('matthew', 'wall-e')
WHERE
    MAKE_DATE(obs.year, obs.month, obs.day) >= DATE('{load_start_date}') - INTERVAL 1 DAY
    AND obs.ts_started >= TIMESTAMP('{load_start_date}')
    AND trc.environment = 'prod'
    AND trc.id_session IS NOT NULL
    AND LOWER(obs.name) IN (
        'ask_user_preferences',
        'send_proposal',
        'handle_segments_without_proposals',
        'handle_negotiation_cancelled',
        'confirm_negotiation',
        'create_negotiation',
        'collectionsinput',
        'outbound_payload_from_dto',
        'handle_collections_data_error',
        'fetch_collections_data',
        'handle_no_contracts',
        'fetch_contracts',
        'paymentallegationtool',
        'debtretrievertool',
        'userdebtclassifiertool',
        'debtfindertool',
        'get_yearly_paid_invoices_report_tool',
        'negotiationproposertool',
        'debt_summary_display_helper',
        'original_invoice_values_disagreement_helper',
        'ongoing_deal_renegotiation_request_helper',
        'handle_non_tenant'
    )
GROUP BY
    trc.id_session
