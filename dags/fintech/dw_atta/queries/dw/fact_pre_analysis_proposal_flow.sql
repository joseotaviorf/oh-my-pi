WITH rnm_offer_pre_analysis AS (
SELECT
    *,
    row_number() OVER (PARTITION BY opa.pre_analysis_id ORDER BY opa.pre_analysis_id, opa.updated_at DESC) AS num_linha
FROM
    datalake_risk_and_mortgage_raw.offer_pre_analysis AS opa
WHERE
    offer_id NOT LIKE '%-old'
    AND offer_id NOT LIKE '%-reproc'
)
SELECT
    COALESCE(CONCAT(COALESCE(cs.id_pre_analysis, pp.id_pre_analysis, ''), COALESCE(pp.id_proposal, '')),-1) AS sk_pre_analysis_proposal_flow,
    COALESCE(cs.id_pre_analysis, pp.id_pre_analysis,-1) AS sk_pre_analysis,
    COALESCE(pp.id_proposal,-1) AS sk_proposal,
    COALESCE(pp.id_proposal_product,-1) AS sk_proposal_product,
    COALESCE(cs.id_offer, pp.id_offer, -1) AS sk_offer,
    COALESCE(pp.id_client, -1) AS sk_client,
    COALESCE(fo.sk_buyer,-1) AS sk_buyer,
    COALESCE(pp.id_multibank_typist_user,-1) AS sk_multibank_typist_user,
    COALESCE(pp.created_by,-1) AS sk_proposal_created_by,
    COALESCE(f.id_provider,-1) AS sk_bank,
    COALESCE(pr.id_product,-1) AS sk_product,
    COALESCE(pp.id_proposal_status,-1) AS sk_proposal_status,
    COALESCE(pp.id_proposal_situation,-1) AS sk_proposal_situation,
    COALESCE(fr.id_franchise,-1) AS sk_franchise,
    COALESCE(pc.id_partner,-1) AS sk_partner,
    COALESCE(cs.id_registration_user,-1) AS sk_registration_user,
    COALESCE(pp.id_consultant,-1) AS sk_consultant,
    reg_user.user_name || ' ' || reg_user.user_last_name AS registration_user_name,
    pp.send_backoffice,
    CASE
        WHEN dsa.is_ccv_canceled = true
            THEN true
        WHEN fo.sk_offer_rescued_date > fo.sk_offer_dismissed_date
            THEN false
        WHEN fo.sk_offer_dismissed_date > 0
            THEN true
        WHEN fo.sk_offer_dismissed_date < 0
            THEN false
    END AS is_offer_canceled,
    nullif(fo.sk_offer_submitted_date,-1) AS dt_offer_submitted,
    nullif(fo.sk_offer_accepted_date,-1) AS dt_offer_accepted,
    nullif(fo.sk_sale_agreement_signed_date,-1) AS dt_sale_agreement_signed,
    nullif(COALESCE(fo.sk_offer_dismissed_date, fcf.sk_sale_agreement_cancelled_date), -1) AS dt_offer_canceled,
    CASE
        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) >= date '2022-08-22'
            THEN COALESCE(date(opa.created_at), (cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) < date '2022-08-22'
            THEN COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
    END AS ts_registration,
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
    CASE
    --next step is filled >> default LT
        WHEN proposal_dates.ts_min_credit_application IS NOT NULL THEN DATEDIFF(
                DATE(proposal_dates.ts_min_credit_application),
                DATE(
                    CASE
                        WHEN DATE(COALESCE(cs.ts_registration, (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) >= date '2022-08-22'
                            THEN COALESCE(date(opa.created_at), (cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                        WHEN DATE(COALESCE(cs.ts_registration, (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) < date '2022-08-22'
                            THEN COALESCE(cs.ts_registration, (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                    END
                ))
    --next step is null, curent filled and has cancelling date >> LT from begining of process to cancelled
        WHEN proposal_dates.ts_min_credit_application IS NULL AND proposal_dates.ts_first_cancelation IS NOT NULL
            THEN DATEDIFF(
                DATE(proposal_dates.ts_first_cancelation),
                DATE(
                    CASE
                        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) >= date '2022-08-22'
                            THEN COALESCE(date(opa.created_at), (cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) < date '2022-08-22'
                            THEN COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                    END
                ))
    --next step is null, curent filled and has no cancelling date, but is cancelled >> NULL
        WHEN proposal_dates.ts_min_credit_application IS NULL AND proposal_dates.ts_first_cancelation IS NULL
        AND pp.id_proposal_situation IN (4, 5) THEN NULL
    END AS days_pre_analysis_registration_to_credit_application_started,
    -- LT from pre analysis to credit
    CASE
    --next step is filled >> default LT
        WHEN proposal_dates.ts_credit_ended IS NOT NULL THEN DATEDIFF(
                DATE(proposal_dates.ts_max_credit_application),
                DATE(
                    CASE
                        WHEN DATE(COALESCE(cs.ts_registration, (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) >= date '2022-08-22'
                            THEN COALESCE(date(opa.created_at), (cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                        WHEN DATE(COALESCE(cs.ts_registration, (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) < date '2022-08-22'
                            THEN COALESCE(cs.ts_registration, (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                    END
                ))
    --next step is null, curent filled and has cancelling date >> default LT
        WHEN proposal_dates.ts_credit_ended IS NULL AND proposal_dates.ts_min_credit_application IS NOT NULL AND pp.id_proposal_situation IN (4, 5)
            THEN DATEDIFF(
                DATE(proposal_dates.ts_max_credit_application),
                DATE(
                    CASE
                        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) >= date '2022-08-22'
                            THEN COALESCE(date(opa.created_at), (cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) < date '2022-08-22'
                            THEN COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                    END
                ))
    END AS days_pre_analysis_registration_to_credit_application_ended,
    CASE
    --next step is filled >> default LT
        WHEN proposal_dates.ts_credit_ended IS NOT NULL THEN DATEDIFF( DATE(proposal_dates.ts_max_credit_application), DATE(proposal_dates.ts_min_credit_application))
    --next step is null, curent filled and is canceled >> default LT
        WHEN proposal_dates.ts_credit_ended IS NULL AND proposal_dates.ts_min_credit_application IS NOT NULL
        AND pp.id_proposal_situation IN (4, 5) THEN DATEDIFF(DATE(proposal_dates.ts_max_credit_application), DATE(proposal_dates.ts_min_credit_application))
    END AS days_credit_application_started_to_credit_application_ended,
    CASE
    --next step is filled >> default LT
        WHEN proposal_dates.ts_min_checklist IS NOT NULL THEN DATEDIFF( DATE(proposal_dates.ts_max_inspection), DATE(proposal_dates.ts_max_credit_application))
    --next step is null, curent filled and is canceled >> default LT
        WHEN proposal_dates.ts_min_checklist IS NULL AND proposal_dates.ts_min_inspection IS NOT NULL
        AND pp.id_proposal_situation IN (4, 5) THEN DATEDIFF( DATE(proposal_dates.ts_max_inspection), DATE(proposal_dates.ts_max_credit_application))
    END AS days_credit_application_ended_to_inspection_ended,
    CASE
    --next step is filled >> default LT
        WHEN proposal_dates.ts_min_bank_application IS NOT NULL THEN DATEDIFF( DATE(proposal_dates.ts_max_checklist), DATE(proposal_dates.ts_max_inspection))
    --next step is null, curent filled and is canceled >> default LT
        WHEN proposal_dates.ts_min_bank_application IS NULL AND proposal_dates.ts_min_checklist IS NOT NULL
        AND pp.id_proposal_situation IN (4, 5) THEN DATEDIFF( DATE(proposal_dates.ts_max_checklist), DATE(proposal_dates.ts_max_inspection))
    END AS days_inspection_ended_to_checklist_ended,
    CASE
    --next step is filled >> default LT
        WHEN proposal_dates.ts_min_financing_contract IS NOT NULL THEN DATEDIFF( DATE(ts_max_bank_application), DATE(proposal_dates.ts_max_checklist))
    --next step is null, curent filled and is canceled >> default LT
        WHEN proposal_dates.ts_min_financing_contract IS NULL AND proposal_dates.ts_min_bank_application IS NOT NULL
        AND pp.id_proposal_situation IN (4, 5) THEN DATEDIFF( DATE(ts_max_bank_application), DATE(proposal_dates.ts_max_checklist))
    END AS days_checklist_ended_to_bank_application_ended,
    CASE
    --next step is filled >> default LT
        WHEN (pp.ts_financing_ended) IS NOT NULL THEN DATEDIFF( DATE((pp.ts_financing_ended)), DATE(proposal_dates.ts_max_bank_application))
    --next step is null, curent filled and is canceled >> LT begining of process until the last conf/emission date
        WHEN (pp.ts_financing_ended) IS NULL AND proposal_dates.ts_min_financing_contract IS NOT NULL
        AND pp.id_proposal_situation IN (4, 5) THEN DATEDIFF( DATE(proposal_dates.ts_max_financing_contract), DATE(proposal_dates.ts_max_bank_application))
    END AS days_bank_application_ended_to_financing_ended,
    CASE
        --proposal with canceled/reproved or finished status
        WHEN pp.id_proposal_situation IN (4, 5) OR pp.ts_financing_ended IS NOT NULL OR pp.id_proposal_status = 5 THEN NULL
        --proposal with conference/emission status >> conference/emission ongoing leadtime
        WHEN pp.id_proposal_status = '7' THEN DATEDIFF( DATE(current_date), DATE(proposal_dates.ts_max_bank_application))
        --proposal with contracting status >> contracting ongoing leadtime
        WHEN pp.id_proposal_status = 4 THEN DATEDIFF( DATE(current_date), DATE(proposal_dates.ts_max_checklist))
        --proposal with checklist status >> checklist ongoing leadtime
        WHEN pp.id_proposal_status = 6 THEN DATEDIFF(DATE(current_date), DATE(proposal_dates.ts_max_inspection))
        --proposal with survey status >> survey ongoing leadtime
        WHEN pp.id_proposal_status = 3 THEN DATEDIFF( DATE(current_date), DATE(proposal_dates.ts_max_credit_application))
        --proposal with credit analysis status >> credit analysis ongoing leadtime
        WHEN pp.id_proposal_status = 2 THEN DATEDIFF( DATE(current_date), DATE(proposal_dates.ts_min_credit_application))
        --proposal with pre analysis status >> pre analysis ongoing leadtime
        WHEN pp.id_proposal_status = 1 OR pp.id_proposal_status IS NULL  THEN DATEDIFF(
                DATE(current_date),
                DATE(
                    CASE
                        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) >= date '2022-08-22'
                            THEN COALESCE(date(opa.created_at), (cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                        WHEN DATE(COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)) < date '2022-08-22'
                            THEN COALESCE((cs.ts_registration), (pp.ts_registration), proposal_dates.ts_min_pre_analysis)
                    END
                ))
    END AS days_ongoing_proposal_status,
    DATEDIFF( DATE(pp.ts_financing_ended), DATE(proposal_dates.ts_min_credit_application)) AS days_credit_application_started_to_financing_ended,
    pp.ts_last_updated
FROM
    datalake_atta_clean.pre_analysis AS cs
FULL OUTER JOIN
    datalake_atta_clean.proposal AS pp ON pp.id_pre_analysis = cs.id_pre_analysis
LEFT JOIN
    rnm_offer_pre_analysis AS opa ON cs.id_pre_analysis = opa.pre_analysis_id AND opa.num_linha = 1
LEFT JOIN
    datalake_atta_clean.product_info AS pr ON pp.id_product = pr.id_product
LEFT JOIN
    datalake_atta_clean.track_step_detail AS pre ON pre.decision_number = pp.id_proposal_status AND pre.id_product = pr.id_product
LEFT JOIN
    datalake_atta_clean.partner_info AS pc
        ON COALESCE(pp.id_partner, cs.id_partner) = pc.id_partner
LEFT JOIN
    datalake_atta_clean.users_info AS u ON pp.id_consultant = u.id_user
LEFT JOIN
    datalake_atta_clean.users_info AS reg_user ON cs.id_registration_user = reg_user.id_user
LEFT JOIN
    datalake_atta_clean.providers_info AS f ON pp.id_emission_provider = f.id_provider
LEFT JOIN
    datalake_atta_clean.franchise_info AS fr ON COALESCE(pp.id_franchise, cs.id_franchise) = fr.id_franchise
LEFT JOIN
    datalake_atta_clean.financing_proposal AS ppi ON pp.id_proposal_product = ppi.id_proposal_product
LEFT JOIN
    datalake_atta_clean.financing_proposal_check AS conf ON pp.id_proposal_product = conf.id_proposal_product
LEFT JOIN
    datalake_atta.proposal_dates ON pp.id_proposal = proposal_dates.id_proposal
LEFT JOIN
    dw_sale.fact_offers AS fo ON COALESCE(cs.id_offer, pp.id_offer) = fo.sk_offer
LEFT JOIN
    dw_sale.dim_sale_agreement AS dsa ON COALESCE(cs.id_offer, pp.id_offer) = dsa.sk_offer
LEFT JOIN
    dw_sale.fact_closing_flows AS fcf ON COALESCE(cs.id_offer, pp.id_offer) = fcf.sk_offer
WHERE
    pr.id_product IN (1,11)
    OR pp.id_proposal IS NULL
