WITH credit_analysis_ordered AS (
  SELECT
    id_proposal,
    id_credit_analysis,
    id_variant,
    category,
    bypass,
    ts_updated
  FROM
    datalake_sorting_hat_clean.credit_analysis
  ORDER BY
    id_proposal, ts_updated
),

credit_analysis_proposals AS (
  SELECT
    id_proposal,
    FIRST(id_credit_analysis) AS id_first_credit_analysis,
    LAST(id_credit_analysis) AS id_last_credit_analysis,
    FIRST(id_variant) AS id_first_variant,
    LAST(id_variant) AS id_last_variant,
    FIRST(category) AS first_category,
    LAST(category) AS last_category,
    LAST(category, true) AS last_category_not_null,
    MAX(bypass) AS max_bypass
  FROM
    credit_analysis_ordered
  WHERE
    id_proposal IS NOT NULL
  GROUP BY 1
),

credit_evaluations AS (
  SELECT
    id_proposal,
    COUNT(DISTINCT id) AS number_evaluations,
    MIN(
      CASE
        WHEN result IN ('PRE_APPROVED', 'REGULAR') THEN ts_updated
      END
    ) AS ts_first_credit_evaluation_positive,
    MAX(
      CASE
        WHEN result IN ('PRE_APPROVED', 'REGULAR') THEN ts_updated
      END
    ) AS ts_last_credit_evaluation_positive
  FROM
    datalake_docx_clean.credit_evaluation
  WHERE
    status = 'FINISHED'
  GROUP BY 1
)

SELECT
  cap.id_proposal,
  rg.id_documentation_ebdb AS id_proposal_from_rg,
  cap.id_first_credit_analysis,
  cap.id_last_credit_analysis,
  cap.id_first_variant,
  cap.id_last_variant,
  rg.score AS guarantee_category,
  rg.guarantee_type AS paid_guarantee_type,
  ct.guarantee_type,
  rg.guarantee_source,
  cr.liquidity,
  cr.risk_category,
  cap.first_category,
  cap.last_category,
  cap.last_category_not_null,
  cap.max_bypass,
  cr.score AS internal_score,
  ceval.number_evaluations,
  ceval.ts_first_credit_evaluation_positive,
  ceval.ts_last_credit_evaluation_positive
FROM
  credit_analysis_proposals AS cap
LEFT JOIN
  credit_evaluations AS ceval
    ON cap.id_proposal = ceval.id_proposal
LEFT JOIN
  datalake_sorting_hat_clean.screening_result AS cr
    ON cap.id_proposal = cr.id_proposal
LEFT JOIN
  datalake_rental_guarantee.guarantee AS rg
    ON cap.id_proposal = rg.id_documentation_ebdb
LEFT JOIN
  datalake_ebdb_clean.contract AS ct
    ON cap.id_proposal = ct.id_proposal