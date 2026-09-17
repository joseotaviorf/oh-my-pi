SELECT
    trc.id_session AS id_langfuse_session,
    -- Group 1: Negotiation flow signals
    MAX(CASE WHEN LOWER(obs.name) = 'ask_user_preferences' THEN 1 ELSE 0 END) AS flag_ask_user_preferences,
    SUM(CASE WHEN LOWER(obs.name) = 'send_proposal' THEN 1 ELSE 0 END) AS send_proposal_count,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_segments_without_proposals' THEN 1 ELSE 0 END) AS flag_handle_segments_without_proposals,
    SUM(CASE WHEN LOWER(obs.name) = 'handle_negotiation_cancelled' THEN 1 ELSE 0 END) AS handle_negotiation_cancelled_count,
    SUM(CASE WHEN LOWER(obs.name) = 'confirm_negotiation' THEN 1 ELSE 0 END) AS confirm_negotiation_count,
    -- MCP-based confirmation count: each null-output create_negotiation_v1 TOOL observation
    -- represents one confirmation prompt sent to the user before committing the deal.
    SUM(CASE WHEN LOWER(obs.name) = 'create_negotiation_v1' AND obs.type = 'TOOL' AND obs.output IS NULL THEN 1 ELSE 0 END) AS confirm_negotiation_count_v3,
    MAX(CASE WHEN LOWER(obs.name) = 'create_negotiation' THEN 1 ELSE 0 END) AS flag_create_negotiation,
    -- Group 2: Matthew technical-state signals
    MAX(CASE WHEN LOWER(obs.name) = 'collectionsinput' THEN 1 ELSE 0 END) AS flag_collectionsinput_agent,
    MAX(CASE WHEN LOWER(obs.name) IN ('collectionsagentv1input', 'collectionsagentv3input') THEN 1 ELSE 0 END) AS flag_collectionsinputv3_agent,
    MAX(
        CASE
            WHEN LOWER(obs.name) = 'collectionsinput'
                OR LOWER(obs.name) RLIKE '^collectionsagentv[0-9]+input$'
            THEN 1
            ELSE 0
        END
    ) AS flag_collections_agent_input,
    MAX(
        CASE
            WHEN LOWER(obs.name) = 'collectionsagentv1input' THEN 3
            WHEN LOWER(obs.name) RLIKE '^collectionsagentv[0-9]+input$'
                THEN CAST(
                    REGEXP_EXTRACT(
                        LOWER(obs.name),
                        '^collectionsagentv([0-9]+)input$',
                        1
                    ) AS INT
                )
            ELSE NULL
        END
    ) AS collections_agent_version,
    MAX(CASE WHEN LOWER(obs.name) = 'outbound_payload_from_dto' THEN 1 ELSE 0 END) AS is_notification_reply,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_collections_data_error' AND obs.type IN ('CHAIN', 'TOOL') THEN 1 ELSE 0 END) AS flag_has_collections_data_error,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_finance_fetch_error' THEN 1 ELSE 0 END) AS flag_has_finance_fetch_error,
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
    MAX(
        CASE
            WHEN LOWER(obs.name) RLIKE '^collectionsagentv[0-9]+ - reactplanner$'
                AND obs.output LIKE '%TalkToUserToolInput%'
            THEN 1
            ELSE 0
        END
    ) AS flag_react_planner_talk_to_user,
    MAX(
        CASE
            WHEN LOWER(obs.name) = 'collectionsinput'
                AND GET_JSON_OBJECT(obs.output, '$.values') LIKE '%RESPOND EXACTLY%'
            THEN 1
            ELSE 0
        END
    ) AS flag_collectionsinput_talk_to_user,
    -- Group 4: Helpers and edge-case handlers
    MAX(CASE WHEN LOWER(obs.name) = 'debt_summary_display_helper' THEN 1 ELSE 0 END) AS flag_debt_summary_display_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'original_invoice_values_disagreement_helper' THEN 1 ELSE 0 END) AS flag_original_invoice_values_disagreement_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'ongoing_deal_renegotiation_request_helper' THEN 1 ELSE 0 END) AS flag_ongoing_deal_renegotiation_request_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'outbound_debt_responsibility_denial_helper' THEN 1 ELSE 0 END) AS flag_outbound_responsibility_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'authentication_helper' THEN 1 ELSE 0 END) AS flag_authentication_helper,
    MAX(CASE WHEN LOWER(obs.name) = 'handle_non_tenant' THEN 1 ELSE 0 END) AS flag_handle_non_tenant,
    MAX(
        CASE
            WHEN UPPER(obs.type) = 'TOOL'
                AND LOWER(obs.name) IN ('get_annual_tax_report_v1', 'get_paid_invoices_annual_report_v1', 'get_yearly_paid_invoices_report_tool')
                AND (
                    LOWER(obs.output) LIKE '%prorated rent%'
                    OR LOWER(obs.output) LIKE '%adjustments to the rent value%'
                )
            THEN 1
            ELSE 0
        END
    ) AS has_prorated_rent_error,
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
LEFT SEMI JOIN
    datalake_chatbot.sessions AS cs
        ON cs.id_langfuse_session = trc.id_session
        AND cs.bot IN ('matthew', 'wall-e')
WHERE
    obs.ts_started >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
    AND trc.environment = 'prod'
    AND trc.id_session IS NOT NULL
    AND (
        LOWER(obs.name) IN (
            'ask_user_preferences',
            'send_proposal',
            'handle_segments_without_proposals',
            'handle_negotiation_cancelled',
            'confirm_negotiation',
            'create_negotiation_v1',
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
            'outbound_debt_responsibility_denial_helper',
            'authentication_helper',
            'handle_non_tenant',
            'handle_finance_fetch_error',
            'get_annual_tax_report_v1',
            'get_paid_invoices_annual_report_v1'
        )
        OR LOWER(obs.name) RLIKE '^collectionsagentv[0-9]+input$'
        OR LOWER(obs.name) RLIKE '^collectionsagentv[0-9]+ - reactplanner$'
    )
GROUP BY
    trc.id_session
