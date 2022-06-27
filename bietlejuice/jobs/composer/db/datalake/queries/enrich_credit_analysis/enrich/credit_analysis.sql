WITH credit_analysis_versions AS (
  SELECT
    id_credit_analysis_version AS id_credit_analysis,
    MAX(NULLIF(category, -1)) AS max_ca_category
  FROM
    datalake_sorting_hat_clean.credit_analysis_version
  GROUP BY 1
)

SELECT
  ca.id_credit_analysis,
  ca.id_proposal,
  ca.id_analyst,
  ca.bypass,
  ca.category,
  COALESCE(ca.category, cav.max_ca_category) AS category_within_ca,
  COALESCE(COALESCE(ca.category, cav.max_ca_category), cap.last_category_not_null) AS category_within_proposal,
  ca.type AS documentation_policy,
  cap.guarantee_category,
  ca.level,
  cap.liquidity,
  cap.paid_guarantee_type,
  CASE
    WHEN rsc.standalone_factor = 0.96 THEN '8%'
    WHEN rsc.standalone_factor = 1.20 THEN '10%'
  END AS standalone_factor,
  ca.reason,
  cap.risk_category,
  cap.internal_score,
  cap.max_bypass,
  cav.max_ca_category,
  ca.result,
  CASE
    WHEN ca.id_proposal IS NULL THEN 'Error'
    WHEN ca.bypass IS NOT NULL AND cap.id_proposal_from_rg IS NULL THEN 'bypass'
    WHEN cap.max_bypass IS NOT NULL AND cap.id_proposal_from_rg IS NULL THEN 'bypass max'
    WHEN (
      (COALESCE(COALESCE(ca.category, cav.max_ca_category), cap.last_category_not_null) = 0)
      OR (cap.guarantee_type = 'SeguroFairfax')
    )
      AND cap.id_proposal_from_rg IS NULL THEN 'Free'
    WHEN COALESCE(COALESCE(ca.category, cav.max_ca_category), cap.last_category_not_null) = 0 THEN 'Free'
    WHEN rsc.is_standalone_allowed = TRUE THEN 'Brokerage Only'
    WHEN rsc.is_guarantee_allowed = TRUE AND rsc.is_deposit_allowed = FALSE AND rsc.is_pro_guarantor_allowed = FALSE THEN 'Insurance' 
    WHEN rsc.is_guarantee_allowed = FALSE AND rsc.is_deposit_allowed = FALSE AND rsc.is_pro_guarantor_allowed = TRUE THEN 'Pro Guarantor'
    WHEN rsc.is_guarantee_allowed = TRUE AND rsc.is_deposit_allowed = TRUE AND rsc.is_pro_guarantor_allowed = FALSE THEN 'Insurance or Deposit'
    WHEN rsc.is_guarantee_allowed = FALSE AND rsc.is_deposit_allowed = TRUE AND rsc.is_pro_guarantor_allowed = TRUE THEN 'Pro Guarantor or Deposit'
    WHEN rsc.is_guarantee_allowed = FALSE AND rsc.is_deposit_allowed = TRUE AND rsc.is_pro_guarantor_allowed = FALSE THEN 'Deposit'
    WHEN cap.ts_first_credit_evaluation_positive IS NOT NULL OR cap.guarantee_source = 'CRM_DOCUMENTATION_ANALYSIS' THEN 'ea_approved'
    WHEN COALESCE(COALESCE(ca.category, cav.max_ca_category), cap.last_category_not_null) IS NULL THEN 'Clear-No'
    ELSE 'Error'
  END AS credit_decision_cluster,
  IF(ca.id_analyst IS NULL, FALSE, TRUE) AS is_manual_analysis,
  CASE
    WHEN cap.guarantee_source = 'CRM_DOCUMENTATION_ANALYSIS' THEN TRUE
    ELSE FALSE
  END AS is_reprocessed,
  ca.ts_created AS ts_credit_analysis_created
FROM
  datalake_sorting_hat_clean.credit_analysis AS ca 
LEFT JOIN
  datalake_credit_analysis.credit_analysis_proposals AS cap
    ON ca.id_proposal = cap.id_proposal
LEFT JOIN
  credit_analysis_versions AS cav
    ON ca.id_credit_analysis = cav.id_credit_analysis
LEFT JOIN
  datalake_rental_guarantee_clean.risk_category AS rsc
    ON rsc.category_level = COALESCE(cap.guarantee_category, COALESCE(COALESCE(ca.category, cav.max_ca_category), cap.last_category_not_null))