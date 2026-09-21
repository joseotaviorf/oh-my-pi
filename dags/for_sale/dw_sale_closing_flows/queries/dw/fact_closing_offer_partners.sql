WITH filtered_offers AS (
    SELECT
        fpp.sk_offer
    FROM
        dw_atta.fact_pre_analysis_proposal_flow AS fpp
    WHERE
        fpp.sk_offer != '-1'
        AND fpp.is_most_advanced = 1
    GROUP BY
        fpp.sk_offer
    HAVING
        COUNT(DISTINCT fpp.sk_pre_analysis) = 1 -- Existe um bug no atta que pode causar duplicidade de sk_pre_analysis para um sk_offer no caso de pessoas comprando mais de um imóvel (pre-analise atrelado ao CPF reutiliza offer_id)
),
dim_proposal_atta_ranked AS (
    SELECT
        dp.sk_proposal,
        dp.financing_value,
        ROW_NUMBER() OVER (
            PARTITION BY dp.sk_proposal
            ORDER BY dp.ts_load DESC
        ) AS rn
    FROM
        dw_atta.dim_proposal_atta AS dp
    WHERE
        dp.sk_proposal > 0
),
dim_proposal_atta_latest AS (
    SELECT
        sk_proposal,
        financing_value
    FROM
        dim_proposal_atta_ranked
    WHERE
        rn = 1
),
most_advanced_proposal AS (
    SELECT
        fpp.sk_offer,
        fpp.sk_pre_analysis,
        dp.sk_proposal,
        dp.financing_value,
        fpp.ts_last_updated,
        DATE(fpp.ts_max_credit_application_approval) AS dt_last_credit_approved,
        DATE(fpp.ts_credit_ended) AS dt_credit_ended,
        DATE(fpp.ts_financing_ended) AS dt_financing_ended,
        DATE(fpp.ts_registration) AS dt_first_pre_analysis,
        DATE(fpp.ts_credit_started) AS dt_credit_started,
        DATE(fpp.ts_min_credit_application_approval) AS dt_credit_approved,
        DATE_TRUNC('day', fpp.ts_min_inspection) AS ts_first_inspection,
        DATE_TRUNC('day', fpp.ts_max_inspection) AS ts_last_inspection,
        DATE_TRUNC('day', fpp.ts_min_checklist) AS ts_first_checklist,
        DATE_TRUNC('day', fpp.ts_max_checklist) AS ts_last_checklist,
        DATE_TRUNC('day', fpp.ts_bank_legal_analysis_started) AS ts_first_bank_legal_analysis_started,
        DATE_TRUNC('day', fpp.ts_bank_legal_analysis_ended) AS ts_last_bank_legal_analysis_ended,
        DATE_TRUNC('day', fpp.ts_min_financing_contract) AS ts_first_financing_contract,
        DATE_TRUNC('day', fpp.ts_max_financing_contract) AS ts_last_financing_contract,
        DATE_TRUNC('day', fpp.ts_min_contracted) AS ts_first_contracted,
        DATE_TRUNC('day', fpp.ts_max_contracted) AS ts_last_contracted,
        DATE_TRUNC('day', fpp.ts_financing_started) AS ts_first_financing_started
    FROM
        dw_atta.fact_pre_analysis_proposal_flow AS fpp
    INNER JOIN
        filtered_offers AS filt_offer
            ON fpp.sk_offer = filt_offer.sk_offer
    INNER JOIN
        dim_proposal_atta_latest AS dp
            ON fpp.sk_proposal = dp.sk_proposal
    WHERE
        fpp.is_most_advanced = 1
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
        WHEN ca.dt_credit_ended IS NOT NULL THEN '1'
        ELSE NULL
    END AS internal_vendors_flag,
    fo.days_offer_accepted_to_sale_agreement_signed,
    fo.days_offer_submitted_to_offer_accepted,
    fo.days_offer_submitted_to_sale_agreement_signed,
    DATEDIFF(ca.dt_last_credit_approved, fo.ts_offer_submitted) AS days_offer_submitted_to_credit_approved,
    DATEDIFF(ca.dt_credit_ended, fo.ts_offer_submitted) AS days_offer_submitted_to_credit_ended,
    DATEDIFF(ca.dt_financing_ended, fo.ts_offer_submitted) AS days_offer_submitted_to_financing_ended,
    DATEDIFF(ca.dt_financing_ended, ca.dt_credit_ended) AS days_credit_ended_to_financing_ended,
    DATEDIFF(ca.dt_financing_ended, ca.dt_last_credit_approved) AS days_credit_approved_to_financing_ended,
    DATEDIFF(ca.dt_last_credit_approved, fo.ts_sale_agreement_signed) AS days_CCV_to_credit_approved,
    DATEDIFF(ca.dt_credit_ended, fo.ts_sale_agreement_signed) AS days_CCV_to_credit_ended,
    DATEDIFF(ca.dt_financing_ended, fo.ts_sale_agreement_signed) AS days_CCV_to_financing_ended,
    fo.ts_offer_submitted AS ts_offer_sumitted,
    fo.ts_offer_accepted AS ts_offer_accepted,
    fo.ts_sale_agreement_signed AS ts_ccv_signed,
    ca.dt_first_pre_analysis AS dt_first_pre_analysis,
    ca.dt_credit_started AS dt_credit_started,
    ca.dt_credit_approved AS dt_credit_approved,
    ca.dt_credit_ended AS dt_credit_ended,
    ca.ts_first_inspection AS ts_first_inspection,
    ca.ts_last_inspection AS ts_last_inspection,
    ca.ts_first_checklist AS ts_first_checklist,
    ca.ts_last_checklist AS ts_last_checklist,
    ca.ts_first_bank_legal_analysis_started AS ts_first_bank_legal_analysis_started,
    ca.ts_last_bank_legal_analysis_ended AS ts_last_bank_legal_analysis_ended,
    ca.ts_first_financing_contract AS ts_first_financing_contract,
    ca.ts_last_financing_contract AS ts_last_financing_contract,
    ca.ts_first_contracted AS ts_first_contracted,
    ca.ts_last_contracted AS ts_last_contracted,
    ca.ts_first_financing_started AS ts_first_financing_started,
    ca.dt_financing_ended AS dt_financing_ended,
    ca.ts_last_updated AS ts_last_updated_isolve,
    DATE_TRUNC('week', fo.ts_offer_submitted) AS dt_offer_submitted_week,
    DATE_TRUNC('week', fo.ts_offer_accepted) AS dt_offer_accepted_week,
    DATE_TRUNC('week', fo.ts_sale_agreement_signed) AS dt_ccv_signed_week,
    NOW() AS ts_load
FROM
    dw_sale.fact_offers AS fo
LEFT JOIN
    most_advanced_proposal AS ca
        ON fo.sk_offer = ca.sk_offer
WHERE
    fo.ts_offer_submitted >= DATE('2023-02-01')
