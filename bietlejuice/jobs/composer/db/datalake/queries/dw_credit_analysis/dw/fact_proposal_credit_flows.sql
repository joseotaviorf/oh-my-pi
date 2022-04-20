 WITH credit_analysis_limits AS (
    SELECT
        ca.id_proposal,
        ca.id_credit_analysis,
        FIRST_VALUE(ca.id_credit_analysis) OVER (PARTITION BY ca.id_proposal ORDER BY ca.ts_updated) AS id_first_credit_analysis,
        FIRST_VALUE(ca.id_variant) OVER (PARTITION BY ca.id_proposal ORDER BY ca.ts_updated) AS id_first_variant,
        FIRST_VALUE(ca.id_credit_analysis) OVER (PARTITION BY ca.id_proposal ORDER BY ca.ts_updated DESC) AS id_last_credit_analysis,
        ca.category,
        p.guarantee
    FROM
        datalake_sorting_hat_clean.credit_analysis AS ca
    JOIN
        datalake_ebdb_clean.proposal AS p
            ON ca.id_proposal = p.id
    WHERE
        p.id <> -1
        AND p.id IS NOT NULL
)
SELECT 
    cal.id_proposal AS sk_proposal,
    CAST(COALESCE(cal.id_credit_analysis,-1) AS INT) AS sk_credit_analysis,
    sk_client,
    CAST(COALESCE(cal.id_first_credit_analysis,-1) AS INT) AS sk_first_credit_analysis,
    CAST(COALESCE(cal.id_first_variant,-1) AS INT) AS sk_first_variant,
    COALESCE(cal.category,-1) AS sk_guarantee_category,
    CAST(COALESCE(cal.id_last_credit_analysis,-1) AS INT) AS sk_last_credit_analysis,
    flrf.sk_offer,
    flrf.sk_region,
    flrf.sk_offer_submitted_date,
    flrf.sk_offer_approved_date,
    flrf.sk_last_credit_evaluation_init, 
    flrf.sk_last_credit_evaluation_positive,
    flrf.sk_last_credit_evaluation_negative,
    COALESCE(NULLIF(flrf.sk_last_credit_evaluation_positive, -1),
              CASE 
                  WHEN flrf.sk_last_credit_evaluation_positive < 0 
                  AND flrf.sk_last_credit_evaluation_negative > 0 
                  AND cal.category IS NOT NULL
                  AND cal.guarantee = 'RentalGuarantee' THEN flrf.sk_last_credit_evaluation_negative 
              END, -1) sk_credit_evaluation_approved_date,
    flrf.sk_tenant_first_doc_sent_date,
    flrf.sk_tenant_doc_complete_date,
    flrf.sk_credit_analysis_approved_date,
    flrf.sk_guarantee_paid_date,        
    flrf.funnel_step,
    IF(cal.id_first_credit_analysis = cal.id_credit_analysis, True, False) AS is_first_credit_evaluation,
    IF(cal.id_last_credit_analysis = cal.id_credit_analysis, True, False) AS is_last_credit_evaluation,
    NOW() AS ts_load
FROM
    dw_public.fact_listing_rent_flows flrf
INNER JOIN 
    credit_analysis_limits cal
        ON cal.id_proposal = flrf.sk_proposal
WHERE
    sk_last_credit_evaluation_init > 0
    AND flrf.sk_proposal > 0 