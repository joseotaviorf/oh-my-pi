WITH credit_analysis_versions AS (
  SELECT
    id_credit_analysis_version AS id_credit_analysis,
    MAX(NULLIF(category, -1)) AS max_ca_category
  FROM
    datalake_sorting_hat_clean.credit_analysis_version
  GROUP BY 1
),

latest_screening_result AS (
  SELECT
    id_proposal,
    liquidity,
    risk_category_canon,
    score
  FROM
    datalake_sorting_hat_clean.screening_result
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_proposal ORDER BY ts_database_transaction DESC) = 1
),

credit_analysis AS (
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
  ca.reason,
  cap.risk_category,
  sr.risk_category_canon,
  cap.internal_score,
  cap.max_bypass,
  cav.max_ca_category,
  ca.result,
  IF(ca.category IS NULL AND ca.bypass IS NOT NULL, TRUE, FALSE) AS is_bypass,
  cap.id_proposal_from_rg,
  cap.last_category,
  IF(ca.id_analyst IS NULL, FALSE, TRUE) AS is_manual_analysis,
  CASE
    WHEN cap.guarantee_source = 'CRM_DOCUMENTATION_ANALYSIS' THEN TRUE
    ELSE FALSE
  END AS is_reprocessed,
  cap.ts_guarantee_accepted,
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
    latest_screening_result AS sr
      ON sr.id_proposal = ca.id_proposal
)

SELECT
  ca.id_credit_analysis,
  ca.id_proposal,
  ca.id_analyst,
  ca.bypass,
  ca.category,
  ca.category_within_ca,
  ca.category_within_proposal,
  ca.documentation_policy,
  ca.guarantee_category,
  ca.level,
  ca.liquidity,
  ca.paid_guarantee_type,
  ca.reason,
  ca.risk_category,
  ca.risk_category_canon,
  ca.internal_score,
  ca.max_bypass,
  ca.max_ca_category,
  ca.result,
  ca.last_category,
  CASE
    WHEN rsc.category_level = 40
    AND rsc.standalone_factor = 0.96 THEN 'Standalone Low'
    WHEN rsc.category_level = 41
    AND rsc.standalone_factor = 1.20 THEN 'Standalone High'
  END AS standalone_factor,
  CASE
    WHEN rsc.is_standalone_allowed = TRUE THEN 'STANDALONE'
    WHEN rsc.is_third_party_guarantee_allowed = TRUE THEN 'THIRD_PARTY_GUARANTEE'
    WHEN (
      rsc.is_guarantee_allowed = TRUE
      AND rsc.is_deposit_allowed = FALSE
      AND rsc.is_pro_guarantor_allowed = FALSE
    ) THEN 'INSURANCE'
    WHEN (
      rsc.is_guarantee_allowed = FALSE
      AND rsc.is_deposit_allowed = FALSE
      AND rsc.is_pro_guarantor_allowed = TRUE
    ) THEN 'PRO_GUARANTOR'
    WHEN (
      rsc.is_guarantee_allowed = TRUE
      AND rsc.is_deposit_allowed = TRUE
      AND rsc.is_pro_guarantor_allowed = FALSE
    ) THEN 'INSURANCE_OR_DEPOSIT'
    WHEN (
      rsc.is_guarantee_allowed = FALSE
      AND rsc.is_deposit_allowed = TRUE
      AND rsc.is_pro_guarantor_allowed = TRUE
    ) THEN 'PRO_GUARANTOR_OR_DEPOSIT'
    WHEN (
      rsc.is_guarantee_allowed = FALSE
      AND rsc.is_deposit_allowed = TRUE
      AND rsc.is_pro_guarantor_allowed = FALSE
    ) THEN 'DEPOSIT'
    WHEN (rsc.category_level = 0)
    OR (
      ca.is_bypass = TRUE
      AND ca.id_proposal_from_rg IS NULL
    )
    THEN 'FREE'
    WHEN (
      ca.is_bypass = TRUE
      AND ca.paid_guarantee_type IS NOT NULL
    ) THEN ca.paid_guarantee_type
    WHEN (
      ca.category IS NULL
      AND ca.is_bypass = FALSE
      AND ca.reason IN ('CLEAR_NO')
    ) THEN 'CLEAR_NO'
    WHEN ca.category = -1 THEN 'UNDEFINED'
    ELSE NULL
  END AS guarantee_offered,
  CASE
    WHEN (ca.last_category = 0) OR (
      ca.is_bypass = TRUE
      AND ca.id_proposal_from_rg IS NULL
    ) THEN 'FREE'
    WHEN (ca.last_category IS NULL AND ca.is_bypass = FALSE) THEN 'CLEAR_NO'
    WHEN (ca.last_category IS NOT NULL AND ca.id_proposal_from_rg IS NOT NULL) OR (
      ca.is_bypass = TRUE
      AND ca.last_category IS NULL
      AND ca.id_proposal_from_rg IS NOT NULL
    ) THEN ca.paid_guarantee_type
    WHEN (
      ca.id_proposal_from_rg IS NULL
      AND ca.last_category IS NOT NULL
    ) THEN 'NOT_ACCEPTED'
  END AS guarantee_accepted,
  ca.is_manual_analysis,
  ca.is_reprocessed,
  ca.is_bypass,
  ca.ts_guarantee_accepted,
  ca.ts_credit_analysis_created
FROM
  credit_analysis AS ca
  LEFT JOIN datalake_rental_guarantee_clean.risk_category AS rsc
    ON rsc.category_level = ca.category
