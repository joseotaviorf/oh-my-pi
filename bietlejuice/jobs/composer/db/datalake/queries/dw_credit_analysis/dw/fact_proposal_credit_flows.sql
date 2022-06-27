WITH credit_analysis AS (
  SELECT
    id_credit_analysis,
    id_proposal,
    category,
    max_ca_category
  FROM
    datalake_credit_analysis.credit_analysis
)

SELECT
  flrf.sk_client,
  flrf.sk_contract_signed_date,
  CAST(COALESCE(ca.id_credit_analysis, -1) AS INTEGER) AS sk_credit_analysis,
  flrf.sk_credit_analysis_approved_date,
  COALESCE(
    NULLIF(flrf.sk_last_credit_evaluation_positive, -1),
    CASE
      WHEN flrf.sk_last_credit_evaluation_positive < 0
      AND flrf.sk_last_credit_evaluation_negative > 0 
      AND ca.category IS NOT NULL THEN flrf.sk_last_credit_evaluation_negative 
    END, -1
  ) AS sk_credit_evaluation_approved_date,
  CAST(COALESCE(cap.id_first_credit_analysis, -1) AS INTEGER) AS sk_first_credit_analysis,
  CAST(COALESCE(cap.id_first_variant, -1) AS INTEGER) AS sk_first_variant,
  COALESCE(ca.category, -1) AS sk_guarantee_category,
  flrf.sk_guarantee_paid_date,
  CAST(COALESCE(cap.id_last_credit_analysis, -1) AS INTEGER) AS sk_last_credit_analysis,
  flrf.sk_last_credit_evaluation_init,
  flrf.sk_last_credit_evaluation_negative,
  flrf.sk_last_credit_evaluation_positive,
  flrf.sk_offer,
  flrf.sk_offer_approved_date,
  flrf.sk_offer_submitted_date,
  cap.id_proposal AS sk_proposal,
  flrf.sk_region,
  flrf.sk_tenant_doc_complete_date,
  flrf.sk_tenant_first_doc_sent_date,
  flrf.funnel_step,
  IF(cap.id_first_credit_analysis = ca.id_credit_analysis, TRUE, FALSE) AS is_first_credit_evaluation,
  IF(cap.id_last_credit_analysis = ca.id_credit_analysis, TRUE, FALSE) AS is_last_credit_evaluation,
  NOW() AS ts_load
FROM
  dw_public.fact_listing_rent_flows AS flrf
JOIN
  datalake_credit_analysis.credit_analysis_proposals AS cap
    ON cap.id_proposal = flrf.sk_proposal
JOIN
  credit_analysis AS ca
    ON cap.id_proposal = ca.id_proposal
WHERE
  sk_last_credit_evaluation_init > 0
  AND flrf.sk_proposal > 0