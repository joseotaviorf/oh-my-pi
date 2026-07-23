WITH
dw_last_proposal AS (
    SELECT
        fpp.sk_pre_analysis,
        fpp.sk_offer,
        dp.sk_proposal,
        dp.financing_value,
        dp.credit_application_status AS credit_analysis_status,
        fpp.ts_max_credit_application_approval,
        fpp.is_most_advanced,
        fpp.ts_last_updated
    FROM
        dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN
        dw_atta.dim_proposal_atta AS dp
            ON fpp.sk_proposal = dp.sk_proposal
    WHERE
      dp.sk_proposal > 0
      AND fpp.is_most_advanced = 1
      AND fpp.sk_offer != '-1'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY fpp.sk_pre_analysis ORDER BY fpp.sk_proposal_status DESC, fpp.ts_last_updated DESC) = 1
),
dim_financed_proposal AS (
    SELECT
        fpp.sk_offer,
        cd.sk_pre_analysis,
        cd.sk_proposal,
        cd.financing_value,
        cd.ts_last_updated,
        CASE
            WHEN DATE(cd.ts_max_credit_application_approval) IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS is_proposal_approved,
        COUNT(DISTINCT fpp.sk_proposal) AS total_proposal,
        COUNT(DISTINCT CASE WHEN dp.credit_application_status = 'Approved' THEN fpp.sk_proposal ELSE NULL END) AS proposal_approved,
        COUNT(DISTINCT CASE WHEN dp.credit_application_status = 'Reproved' THEN fpp.sk_proposal ELSE NULL END) AS proposal_reproved,
        COUNT(DISTINCT CASE WHEN dp.credit_application_status = 'Incomplete' OR dp.credit_application_status IS NULL THEN fpp.sk_proposal ELSE NULL END) AS proposal_pending,
        MIN(DATE(fpp.ts_registration)) AS first_pre_analysis,
        MIN(DATE(fpp.ts_credit_started)) AS first_credit_started,
        MIN(DATE(fpp.ts_min_credit_application_approval)) AS first_credit_approved_date,
        MAX(DATE(fpp.ts_max_credit_application_approval)) AS last_credit_approved_date,
        MAX(DATE(fpp.ts_credit_ended)) AS credit_ended_isolve,
        MAX(DATE(fpp.ts_credit_ended)) AS credit_ended_date,
        MAX(COALESCE(DATE(fpp.ts_credit_ended), DATE(fpp.ts_credit_ended))) AS last_credit_ended,
        MIN(DATE_TRUNC('day', fpp.ts_min_inspection)) AS first_dt_inspection,
        MIN(DATE_TRUNC('day', fpp.ts_max_inspection)) AS last_dt_inspection,
        MIN(DATE_TRUNC('day', fpp.ts_min_checklist)) AS first_dt_checklist,
        MAX(DATE_TRUNC('day', fpp.ts_max_checklist)) AS last_dt_checklist,
        MIN(DATE_TRUNC('day', fpp.ts_bank_legal_analysis_started)) AS first_dt_bank_legal_analysis_started,
        MAX(DATE_TRUNC('day', fpp.ts_bank_legal_analysis_ended)) AS last_dt_bank_legal_analysis_ended,
        MIN(DATE_TRUNC('day', fpp.ts_min_financing_contract)) AS first_dt_financing_contract,
        MAX(DATE_TRUNC('day', fpp.ts_max_financing_contract)) AS last_dt_financing_contract,
        MIN(DATE_TRUNC('day', fpp.ts_min_contracted)) AS first_dt_contracted,
        MAX(DATE_TRUNC('day', fpp.ts_max_contracted)) AS last_dt_contracted,
        MIN(DATE_TRUNC('day', fpp.ts_financing_started)) AS first_financing_started,
        MAX(DATE(fpp.ts_financing_ended)) AS last_financing_ended
    FROM
      dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN dw_atta.dim_proposal_atta AS dp
        ON fpp.sk_proposal = dp.sk_proposal
    LEFT JOIN dw_last_proposal AS cd
        ON fpp.sk_pre_analysis = cd.sk_pre_analysis
    WHERE
      fpp.sk_proposal > 0
      AND fpp.sk_offer != '-1'
    GROUP BY
        fpp.sk_offer,
        cd.sk_pre_analysis,
        cd.sk_proposal,
        cd.financing_value,
        cd.ts_last_updated,
        cd.ts_max_credit_application_approval
)
SELECT
 fo.sk_offer,
 ca.sk_pre_analysis,
 ca.sk_proposal,
 fo.sk_closing_specialist,
 fo.sk_buyer,
 fo.sk_owner,
 ca.financing_value,
 CASE
    WHEN COALESCE(ca.last_credit_ended, ca.credit_ended_date) IS NOT NULL
    THEN '1'
    ELSE NULL
 END AS internal_vendors_flag,
 fo.days_offer_accepted_to_sale_agreement_signed,
 fo.days_offer_submitted_to_offer_accepted,
 fo.days_offer_submitted_to_sale_agreement_signed,
 DATEDIFF(day, fo.ts_offer_submitted, ca.last_credit_approved_date) AS days_offer_submitted_to_credit_approved,
 DATEDIFF(day, fo.ts_offer_submitted, ca.last_credit_ended) AS days_offer_submitted_to_credit_ended,
 DATEDIFF(day, fo.ts_offer_submitted, ca.last_financing_ended) AS days_offer_submitted_to_financing_ended,
 DATEDIFF(day, ca.last_credit_ended, ca.last_financing_ended) AS days_credit_ended_to_financing_ended,
 DATEDIFF(day, ca.last_credit_approved_date, ca.last_financing_ended) AS days_credit_approved_to_financing_ended,
 DATEDIFF(day, fo.ts_sale_agreement_signed, ca.last_credit_approved_date) AS days_CCV_to_credit_approved,
 DATEDIFF(day, fo.ts_sale_agreement_signed, ca.last_credit_ended) AS days_CCV_to_credit_ended,
 DATEDIFF(day, fo.ts_sale_agreement_signed, ca.last_financing_ended) AS days_CCV_to_financing_ended,
 fo.ts_offer_submitted AS ts_offer_sumitted,
 fo.ts_offer_accepted AS ts_offer_accepted,
 fo.ts_sale_agreement_signed AS ts_ccv_signed,
 ca.first_pre_analysis AS dt_first_pre_analysis,
 ca.first_credit_started AS dt_credit_started,
 ca.first_credit_approved_date AS dt_credit_approved,
 ca.credit_ended_date AS dt_credit_ended,
 ca.first_dt_inspection AS ts_first_inspection,
 ca.last_dt_inspection AS ts_last_inspection,
 ca.first_dt_checklist AS ts_first_checklist,
 ca.last_dt_checklist AS ts_last_checklist,
 ca.first_dt_bank_legal_analysis_started AS ts_first_bank_legal_analysis_started,
 ca.last_dt_bank_legal_analysis_ended AS ts_last_bank_legal_analysis_ended,
 ca.first_dt_financing_contract AS ts_first_financing_contract,
 ca.last_dt_financing_contract AS ts_last_financing_contract,
 ca.first_dt_contracted AS ts_first_contracted,
 ca.last_dt_contracted AS ts_last_contracted,
 ca.first_financing_started AS ts_first_financing_started,
 ca.last_financing_ended AS dt_financing_ended,
 ca.ts_last_updated AS ts_last_updated_isolve,
 DATE_TRUNC('week', fo.ts_offer_submitted) AS dt_offer_submitted_week,
 DATE_TRUNC('week', fo.ts_offer_accepted) AS dt_offer_accepted_week,
 DATE_TRUNC('week', fo.ts_sale_agreement_signed) AS dt_ccv_signed_week,
 NOW() AS ts_load
FROM
    dw_sale.fact_offers AS fo
LEFT JOIN
    dw_sale.dim_sale_agreement AS dsa
        ON fo.sk_offer = dsa.sk_offer
LEFT JOIN
    dim_financed_proposal AS ca
        ON fo.sk_offer = ca.sk_offer
WHERE
    fo.ts_offer_submitted >= DATE('2023-02-01')
