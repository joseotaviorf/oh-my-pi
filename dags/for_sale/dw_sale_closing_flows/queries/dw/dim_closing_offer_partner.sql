WITH dw_last_proposal AS (
    SELECT
        fpp.sk_pre_analysis,
        fpp.sk_offer,
        dfr.franchise_name,
        dpa.partner_name,
        ca.consultant_name,
        dpa.partner_type,
        dp.proposal_status,
        dp.proposal_situation,
        dp.sk_proposal,
        dp.financing_bank,
        dp.financing_value,
        dp.credit_application_status AS credit_analysis_status,
        fpp.ts_max_credit_application_approval,
        fpp.ts_last_updated
    FROM
        dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN
        dw_atta.dim_proposal_atta AS dp
            ON fpp.sk_proposal = dp.sk_proposal
    LEFT JOIN
        dw_atta.dim_partner_atta AS dpa
            ON fpp.sk_partner = dpa.sk_partner
    LEFT JOIN
        dw_atta.dim_franchise_atta AS dfr
            ON fpp.sk_franchise = dfr.sk_franchise
    LEFT JOIN
        dw_atta.dim_consultant_atta AS ca
            ON fpp.sk_consultant = ca.sk_consultant
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
        cd.franchise_name,
        cd.partner_name,
        cd.consultant_name,
        cd.partner_type,
        cd.credit_analysis_status AS last_credit_analysis_status,
        cd.sk_proposal,
        cd.proposal_status,
        cd.proposal_situation,
        cd.financing_bank,
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
        MIN(DATE(fpp.ts_min_credit_application_approval)) AS first_credit_approved_date,
        MIN(DATE(fpp.ts_registration)) AS first_pre_analysis,
        MAX(DATE(fpp.ts_credit_ended)) AS credit_ended_isolve,
        MAX(DATE(fpp.ts_credit_ended)) AS credit_ended_date,
        MAX(COALESCE(DATE(fpp.ts_credit_ended), DATE(fpp.ts_credit_ended))) AS last_credit_ended,
        MAX(DATE(fpp.ts_financing_ended)) AS last_financing_ended
    FROM
        dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN
        dw_atta.dim_proposal_atta AS dp
            ON fpp.sk_proposal = dp.sk_proposal
    LEFT JOIN
        dw_last_proposal AS cd
            ON fpp.sk_pre_analysis = cd.sk_pre_analysis
    WHERE
        fpp.sk_proposal > 0
        AND fpp.sk_offer != '-1'
    GROUP BY ALL
)
SELECT DISTINCT
    fo.sk_offer,
    ca.sk_pre_analysis,
    ca.partner_name,
    ca.franchise_name,
    ca.consultant_name,
    ca.partner_type,
    CASE
        WHEN ca.first_pre_analysis IS NOT NULL AND ca.partner_type IN ('EXTERNAL', 'FRANCHISE')
        THEN 'PARTNER'
        ELSE 'INTERNAL'
    END AS partner_type_group,
    CASE
        WHEN ca.first_credit_approved_date IS NOT NULL
        THEN 'Approved'
        ELSE ca.last_credit_analysis_status
    END AS last_credit_analysis_status,
    ca.financing_bank,
    ca.financing_value,
    ca.proposal_status,
    ca.proposal_situation,
    CASE
        WHEN fo.ts_offer_dismissed IS NOT NULL AND fo.ts_offer_rescued IS NULL OR dsa.ts_sale_agreement_cancelled IS NOT NULL
        THEN TRUE ELSE FALSE
    END AS is_ccv_canceled,
    CASE
        WHEN do.payment_method IN ('FINANCED_USING_FGTS','FINANCED')
        THEN TRUE
        ELSE FALSE
    END AS is_offer_financed,
    CASE
        WHEN fo.ts_offer_dismissed IS NOT NULL AND fo.ts_offer_rescued IS NULL
        THEN TRUE
        ELSE FALSE
    END AS is_offer_canceled,
    CASE
        WHEN fo.ts_offer_accepted IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS is_offer_accepted,
    CASE
        WHEN ca.proposal_approved > 0
        THEN TRUE
        ELSE FALSE
    END AS is_credit_approved,
    CASE
        WHEN ca.last_credit_ended IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS is_credit_ended,
    CASE
        WHEN COALESCE(ca.last_credit_ended, ca.credit_ended_isolve) IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS is_credit_ended_general,
    CASE
        WHEN fo.sk_sale_agreement_signed_date > 0
        THEN TRUE
        ELSE FALSE
    END AS is_ccv_signed,
    CASE
        WHEN ca.last_financing_ended IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS is_financing_ended,
    NOW() AS ts_load
FROM
    dw_sale.fact_offers AS fo
LEFT JOIN
    dw_sale.dim_sale_agreement AS dsa
        ON fo.sk_offer = dsa.sk_offer
LEFT JOIN
    dim_financed_proposal AS ca
        ON fo.sk_offer = ca.sk_offer
LEFT JOIN
    dw_sale.dim_offer  AS do
        ON fo.sk_offer = do.sk_offer
WHERE
    fo.ts_offer_submitted >= DATE('2023-02-01')
