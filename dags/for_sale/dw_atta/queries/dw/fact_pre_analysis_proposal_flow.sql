WITH proposal_excluding_manual_financing_ended AS (
                    -- remove casos de propostas adicionadas manualmente com data de finalização de financiamento anterior à data de registro da proposta
                    SELECT
                        id_proposal,
                        id_client,
                        id_consultant,
                        id_pre_analysis,
                        id_emission_provider,
                        id_franchise,
                        id_partner,
                        id_product,
                        id_offer,
                        id_proposal_product,
                        id_multibank_typist_user,
                        created_by,
                        id_proposal_situation,
                        id_proposal_status,
                        ts_registration,
                        ts_financing_ended,
                        ts_last_updated
                    FROM
                        datalake_atta_clean.proposal
                    WHERE
                        ts_registration < ts_financing_ended OR ts_financing_ended IS NULL
                ),
doc_submission AS (
                    SELECT
                        offer.id_firestore,
                        neg.id_sales_flow,
                        MAX(neg.ts_updated) AS ts_updated
                    FROM
                        datalake_sales_flow_clean.negotiation AS neg
                    LEFT JOIN
                        datalake_sales_flow_clean.offer ON neg.id_sales_flow = offer.id_sales_flow
                        AND offer.ts_created < CURRENT_DATE()
                    WHERE neg.ts_buyer_credit_submitted >= DATE '2022-11-23'
                    GROUP BY 1,2
                ),
pre_analysis_proposal_base AS (
                    SELECT
                        CONCAT(
                            COALESCE(CAST(cs.id_pre_analysis AS STRING), CAST(pp.id_pre_analysis AS STRING), '-1'),
                            '_',
                            COALESCE(CAST(pp.id_proposal AS STRING), '-1')
                        ) AS sk_pre_analysis_proposal_flow,
                        COALESCE(cs.id_pre_analysis, pp.id_pre_analysis,-1) AS sk_pre_analysis,
                        COALESCE(pp.id_proposal,-1) AS sk_proposal,
                        COALESCE(pp.id_proposal_product,-1) AS sk_proposal_product,
                        COALESCE(cs.id_offer, pp.id_offer, -1) AS sk_offer,
                        COALESCE(pp.id_client, cs.id_client, -1) AS sk_client,
                        COALESCE(fo.sk_buyer,-1) AS sk_buyer,
                        COALESCE(pp.id_multibank_typist_user,-1) AS sk_multibank_typist_user,
                        COALESCE(pp.created_by,-1) AS sk_proposal_created_by,
                        COALESCE(f.id_provider,-1) AS sk_bank,
                        COALESCE(pr.id_product,-1) AS sk_product,
                        COALESCE(pp.id_proposal_status,-1) AS sk_proposal_status,
                        -- Rank used only for is_most_advanced* flags: checklist (6) below contracting (4)
                        CASE COALESCE(pp.id_proposal_status, -1)
                            WHEN 2 THEN 1
                            WHEN 6 THEN 2
                            WHEN 4 THEN 3
                            WHEN 7 THEN 4
                            WHEN 32 THEN 5
                            ELSE COALESCE(pp.id_proposal_status, -1)
                        END AS sk_proposal_status_order,
                        COALESCE(pp.id_proposal_situation,-1) AS sk_proposal_situation,
                        COALESCE(fr.id_franchise,-1) AS sk_franchise,
                        COALESCE(pp.id_partner, cs.id_partner, -1) AS sk_partner,
                        COALESCE(cs.id_registration_user,-1) AS sk_registration_user,
                        COALESCE(pp.id_consultant, cs.id_consultant, -1) AS sk_consultant,
                        reg_user.user_name || ' ' || reg_user.user_last_name AS registration_user_name,
                        CASE
                            WHEN dsa.is_ccv_canceled = true THEN true
                            WHEN fo.sk_offer_rescued_date > fo.sk_offer_dismissed_date THEN false
                            WHEN fo.sk_offer_dismissed_date > 0 THEN true
                            WHEN fo.sk_offer_dismissed_date < 0 THEN false
                            ELSE false
                        END AS is_offer_canceled,
                        NULLIF(fo.sk_offer_submitted_date,-1) AS dt_offer_submitted,
                        NULLIF(fo.sk_offer_accepted_date,-1) AS dt_offer_accepted,
                        NULLIF(fo.sk_sale_agreement_signed_date,-1) AS dt_sale_agreement_signed,
                        NULLIF(COALESCE(fo.sk_offer_dismissed_date, fcf.sk_sale_agreement_cancelled_date), -1) AS dt_offer_canceled,
                        COALESCE(cs.ts_registration, pp.ts_registration, proposal_dates.ts_min_pre_analysis) AS ts_registration,
                        proposal_dates.ts_first_cancelation AS ts_proposal_cancelation,
                        proposal_dates.ts_min_credit_application,
                        proposal_dates.ts_max_credit_application,
                        proposal_dates.ts_min_pre_analysis,
                        proposal_dates.ts_max_pre_analysis,
                        proposal_dates.ts_min_credit_application_approval,
                        proposal_dates.ts_max_credit_application_approval,
                        proposal_dates.ts_min_credit_application_reproval,
                        proposal_dates.ts_max_credit_application_reproval,
                        proposal_dates.ts_min_inspection,
                        proposal_dates.ts_max_inspection,
                        proposal_dates.ts_min_checklist,
                        proposal_dates.ts_max_checklist,
                        proposal_dates.ts_min_bank_application,
                        proposal_dates.ts_max_bank_application,
                        proposal_dates.ts_min_financing_contract,
                        proposal_dates.ts_max_financing_contract,
                        proposal_dates.ts_min_contracted,
                        proposal_dates.ts_max_contracted,
                        proposal_dates.ts_credit_started,
                        proposal_dates.ts_credit_ended,
                        proposal_dates.ts_financing_started,
                        proposal_dates.ts_bank_legal_analysis_started,
                        proposal_dates.ts_bank_legal_analysis_ended,
                        pp.ts_financing_ended,
                        proposal_dates.ts_last_approved_log,
                        pp.ts_last_updated,
                        neg.ts_buyer_credit_submitted AS ts_filled_credit_form
                    FROM
                        datalake_atta_clean.pre_analysis AS cs
                    FULL OUTER JOIN
                        proposal_excluding_manual_financing_ended AS pp
                            ON pp.id_pre_analysis = cs.id_pre_analysis
                    LEFT JOIN
                        datalake_atta_clean.product_info AS pr ON pp.id_product = pr.id_product
                    LEFT JOIN
                        datalake_atta_clean.users_info AS reg_user ON cs.id_registration_user = reg_user.id_user
                    LEFT JOIN
                        datalake_atta_clean.providers_info AS f ON pp.id_emission_provider = f.id_provider
                    LEFT JOIN
                        datalake_atta_clean.franchise_info AS fr ON COALESCE(pp.id_franchise, cs.id_franchise) = fr.id_franchise
                    LEFT JOIN
                        datalake_atta.proposal_dates ON pp.id_proposal = proposal_dates.id_proposal
                    LEFT JOIN
                        dw_sale.fact_offers AS fo ON COALESCE(cs.id_offer, pp.id_offer) = fo.sk_offer
                    LEFT JOIN
                        dw_sale.dim_sale_agreement AS dsa ON COALESCE(cs.id_offer, pp.id_offer) = dsa.sk_offer
                    LEFT JOIN
                        dw_sale.fact_closing_flows AS fcf ON COALESCE(cs.id_offer, pp.id_offer) = fcf.sk_offer
                    LEFT JOIN
                        doc_submission AS ds ON ds.id_firestore = COALESCE(cs.id_offer, pp.id_offer)
                    LEFT JOIN
                        datalake_sales_flow_clean.negotiation AS neg ON ds.id_sales_flow = neg.id_sales_flow AND ds.ts_updated = neg.ts_updated
                    ),
pre_analysis_proposal_flow AS (
                    SELECT
                        sk_pre_analysis_proposal_flow,
                        sk_pre_analysis,
                        sk_proposal,
                        sk_proposal_product,
                        sk_offer,
                        sk_client,
                        sk_buyer,
                        sk_multibank_typist_user,
                        sk_proposal_created_by,
                        sk_bank,
                        sk_product,
                        sk_proposal_status,
                        sk_proposal_status_order,
                        sk_proposal_situation,
                        sk_franchise,
                        sk_partner,
                        sk_registration_user,
                        sk_consultant,
                        registration_user_name,
                        is_offer_canceled,
                        --next step is filled >> default LT
                        CASE
                            WHEN ts_min_credit_application IS NOT NULL THEN DATEDIFF(DATE(ts_min_credit_application), DATE(ts_registration))
                        --next step is null, current filled and has cancelling date >> LT from beginning of process to cancelled
                            WHEN ts_min_credit_application IS NULL AND ts_proposal_cancelation IS NOT NULL THEN DATEDIFF(DATE(ts_proposal_cancelation), DATE(ts_registration))
                        --next step is null, current filled and has no cancelling date, but is cancelled >> NULL
                            WHEN ts_min_credit_application IS NULL AND ts_proposal_cancelation IS NULL AND sk_proposal_situation IN (4, 5) THEN NULL
                        END AS days_pre_analysis_registration_to_credit_application_started,
                        CASE
                            WHEN ts_credit_ended IS NOT NULL THEN DATEDIFF(DATE(ts_max_credit_application), DATE(ts_registration))
                            WHEN ts_credit_ended IS NULL AND ts_min_credit_application IS NOT NULL AND sk_proposal_situation IN (4, 5) THEN DATEDIFF(DATE(ts_max_credit_application), DATE(ts_registration))
                        END AS days_pre_analysis_registration_to_credit_application_ended,
                        CASE
                            WHEN ts_credit_ended IS NOT NULL THEN DATEDIFF(DATE(ts_max_credit_application), DATE(ts_min_credit_application))
                            WHEN ts_credit_ended IS NULL AND ts_min_credit_application IS NOT NULL AND sk_proposal_situation IN (4, 5) THEN DATEDIFF(DATE(ts_max_credit_application), DATE(ts_min_credit_application))
                        END AS days_credit_application_started_to_credit_application_ended,
                        CASE
                            WHEN ts_min_checklist IS NOT NULL THEN DATEDIFF(DATE(ts_max_inspection), DATE(ts_max_credit_application))
                            WHEN ts_min_checklist IS NULL AND ts_min_inspection IS NOT NULL AND sk_proposal_situation IN (4, 5) THEN DATEDIFF(DATE(ts_max_inspection), DATE(ts_max_credit_application))
                        END AS days_credit_application_ended_to_inspection_ended,
                        CASE
                            WHEN ts_min_bank_application IS NOT NULL THEN DATEDIFF(DATE(ts_max_checklist), DATE(ts_max_inspection))
                            WHEN ts_min_bank_application IS NULL AND ts_min_checklist IS NOT NULL AND sk_proposal_situation IN (4, 5) THEN DATEDIFF(DATE(ts_max_checklist), DATE(ts_max_inspection))
                        END AS days_inspection_ended_to_checklist_ended,
                        CASE
                            WHEN ts_min_financing_contract IS NOT NULL THEN DATEDIFF(DATE(ts_max_bank_application), DATE(ts_max_checklist))
                            WHEN ts_min_financing_contract IS NULL AND ts_min_bank_application IS NOT NULL AND sk_proposal_situation IN (4, 5) THEN DATEDIFF(DATE(ts_max_bank_application), DATE(ts_max_checklist))
                        END AS days_checklist_ended_to_bank_application_ended,
                        CASE
                            WHEN ts_financing_ended IS NOT NULL THEN DATEDIFF(DATE(ts_financing_ended), DATE(ts_max_bank_application))
                            WHEN ts_financing_ended IS NULL AND ts_min_financing_contract IS NOT NULL AND sk_proposal_situation IN (4, 5) THEN DATEDIFF(DATE(ts_max_financing_contract), DATE(ts_max_bank_application))
                        END AS days_bank_application_ended_to_financing_ended,
                        CASE
                            WHEN sk_proposal_situation IN (4, 5) OR ts_financing_ended IS NOT NULL OR sk_proposal_status = 5 THEN NULL
                            WHEN sk_proposal_status = 7 THEN DATEDIFF(DATE(CURRENT_DATE), DATE(ts_max_bank_application))
                            WHEN sk_proposal_status = 4 THEN DATEDIFF(DATE(CURRENT_DATE), DATE(ts_max_checklist))
                            WHEN sk_proposal_status = 6 THEN DATEDIFF(DATE(CURRENT_DATE), DATE(ts_max_inspection))
                            WHEN sk_proposal_status = 3 THEN DATEDIFF(DATE(CURRENT_DATE), DATE(ts_max_credit_application))
                            WHEN sk_proposal_status = 2 THEN DATEDIFF(DATE(CURRENT_DATE), DATE(ts_min_credit_application))
                            WHEN sk_proposal_status IN (1, -1) THEN DATEDIFF(DATE(CURRENT_DATE), DATE(ts_registration))
                        END AS days_ongoing_proposal_status,
                        DATEDIFF(DATE(ts_financing_ended), DATE(ts_min_credit_application)) AS days_credit_application_started_to_financing_ended,
                        dt_offer_submitted,
                        dt_offer_accepted,
                        dt_sale_agreement_signed,
                        dt_offer_canceled,
                        ts_registration,
                        ts_proposal_cancelation,
                        ts_min_credit_application,
                        ts_max_credit_application,
                        ts_min_pre_analysis,
                        ts_max_pre_analysis,
                        ts_min_credit_application_approval,
                        ts_max_credit_application_approval,
                        ts_min_credit_application_reproval,
                        ts_max_credit_application_reproval,
                        ts_min_inspection,
                        ts_max_inspection,
                        ts_min_checklist,
                        ts_max_checklist,
                        ts_min_bank_application,
                        ts_max_bank_application,
                        ts_min_financing_contract,
                        ts_max_financing_contract,
                        ts_min_contracted,
                        ts_max_contracted,
                        ts_credit_started,
                        ts_credit_ended,
                        ts_financing_started,
                        ts_bank_legal_analysis_started,
                        ts_bank_legal_analysis_ended,
                        ts_financing_ended,
                        ts_last_approved_log,
                        ts_last_updated,
                        ts_filled_credit_form
                    FROM
                        pre_analysis_proposal_base
                    ),
ongoing_proposals AS (
                    SELECT
                        atta.sk_pre_analysis,
                        atta.sk_proposal,
                        ROW_NUMBER() OVER (PARTITION BY atta.sk_pre_analysis ORDER BY atta.sk_proposal_status_order DESC, atta.ts_last_updated DESC) AS num_linha
                    FROM
                        pre_analysis_proposal_flow AS atta
                    WHERE
                        atta.sk_proposal_situation NOT IN (4,5)
                        AND atta.sk_proposal IS NOT NULL
                    ),
canceled_proposals AS (
                    SELECT
                        atta.sk_pre_analysis,
                        atta.sk_proposal,
                        ROW_NUMBER() OVER (PARTITION BY atta.sk_pre_analysis ORDER BY atta.sk_proposal_status_order DESC, atta.ts_last_updated DESC) AS num_linha
                    FROM
                        pre_analysis_proposal_flow AS atta
                    WHERE
                        atta.sk_proposal_situation IN (4,5)
                        AND atta.sk_proposal IS NOT NULL
                    )
SELECT
    f.sk_pre_analysis_proposal_flow,
    f.sk_pre_analysis,
    f.sk_proposal,
    f.sk_proposal_product,
    f.sk_offer,
    f.sk_client,
    f.sk_buyer,
    f.sk_multibank_typist_user,
    f.sk_proposal_created_by,
    f.sk_bank,
    f.sk_product,
    f.sk_proposal_status,
    f.sk_proposal_situation,
    f.sk_franchise,
    f.sk_partner,
    f.sk_registration_user,
    f.sk_consultant,
    f.registration_user_name,
    f.is_offer_canceled,
    CASE WHEN f.sk_proposal = cp.sk_proposal THEN 1 ELSE 0 END AS is_most_advanced_canc,
    CASE WHEN f.sk_proposal = op.sk_proposal THEN 1 ELSE 0 END AS is_most_advanced_og,
    CASE WHEN f.sk_proposal = COALESCE(op.sk_proposal, cp.sk_proposal) THEN 1 ELSE 0 END AS is_most_advanced,
    f.days_pre_analysis_registration_to_credit_application_started,
    f.days_pre_analysis_registration_to_credit_application_ended,
    f.days_credit_application_started_to_credit_application_ended,
    f.days_credit_application_ended_to_inspection_ended,
    f.days_inspection_ended_to_checklist_ended,
    f.days_checklist_ended_to_bank_application_ended,
    f.days_bank_application_ended_to_financing_ended,
    f.days_ongoing_proposal_status,
    f.days_credit_application_started_to_financing_ended,
    f.dt_offer_submitted,
    f.dt_offer_accepted,
    f.dt_sale_agreement_signed,
    f.dt_offer_canceled,
    f.ts_registration,
    f.ts_proposal_cancelation,
    f.ts_min_credit_application,
    f.ts_max_credit_application,
    f.ts_min_pre_analysis,
    f.ts_max_pre_analysis,
    f.ts_min_credit_application_approval,
    f.ts_max_credit_application_approval,
    f.ts_min_credit_application_reproval,
    f.ts_max_credit_application_reproval,
    f.ts_min_inspection,
    f.ts_max_inspection,
    f.ts_min_checklist,
    f.ts_max_checklist,
    f.ts_min_bank_application,
    f.ts_max_bank_application,
    f.ts_min_financing_contract,
    f.ts_max_financing_contract,
    f.ts_min_contracted,
    f.ts_max_contracted,
    f.ts_credit_started,
    f.ts_credit_ended,
    f.ts_financing_started,
    f.ts_bank_legal_analysis_started,
    f.ts_bank_legal_analysis_ended,
    f.ts_financing_ended,
    f.ts_last_approved_log,
    f.ts_last_updated,
    f.ts_filled_credit_form,
    NOW() AS ts_load
FROM pre_analysis_proposal_flow AS f
LEFT JOIN
    canceled_proposals AS cp
        ON cp.sk_pre_analysis = f.sk_pre_analysis AND cp.num_linha = 1
LEFT JOIN
    ongoing_proposals AS op
        ON op.sk_pre_analysis = f.sk_pre_analysis AND op.num_linha = 1
