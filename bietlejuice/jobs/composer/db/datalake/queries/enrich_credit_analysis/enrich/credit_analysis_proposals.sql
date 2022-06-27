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

credit_evaluations_prev AS (
  SELECT
    id_proposal,
    proposal_last_result,
    proposal_number_evaluations,
    ts_proposal_first_credit_evaluation_positive,
    ts_proposal_last_credit_evaluation_positive,
    ROW_NUMBER() OVER(PARTITION BY id_proposal ORDER BY ts_updated DESC, ts_created DESC) AS rn
  FROM
    datalake_docx.credit_evaluation
),

credit_evaluations AS (
  SELECT
    id_proposal,
    proposal_last_result,
    proposal_number_evaluations,
    ts_proposal_first_credit_evaluation_positive,
    ts_proposal_last_credit_evaluation_positive
  FROM
    credit_evaluations_prev
  WHERE
    rn = 1
),

dti AS (
  SELECT
    p.id AS id_proposal,
    NULLIF(SUM(p2.monthly_income),0) AS income,
    MAX(p.rent_value + COALESCE(p.condo_value,0) + COALESCE(p.iptu_value,0) + COALESCE(p.home_insurance_value,0)) AS package,
    CASE 
      WHEN SUM(p2.monthly_income) != 0 THEN CAST(MAX(p.rent_value + COALESCE(p.condo_value,0) + COALESCE(p.iptu_value,0) + COALESCE(p.home_insurance_value,0))/SUM(p2.monthly_income) AS DECIMAL(9,2))
      ELSE NULL 
    END AS dti
  FROM
    datalake_sorting_hat_clean.proposal p 
  LEFT JOIN 
    datalake_sorting_hat_clean.proponent p2 
      ON p.id = p2.id_proposal 
  GROUP BY 1
),

sorting_hat_proposals_prev AS (
  SELECT
    p.id,
    p.status,
    p.ts_analyzed,
    p.ts_processed,
    pv.ts_analyzed AS ts_analyzed_version,
    ROW_NUMBER() OVER (PARTITION by p.id ORDER BY pv.ts_analyzed) AS rn
  FROM
    datalake_sorting_hat_clean.proposal AS p
  LEFT JOIN
    datalake_sorting_hat_clean.proposal_version AS pv
      ON p.id = pv.id_proposal
),

sorting_hat_proposals AS (
  SELECT
    id AS id_proposal,
    status,
    ts_analyzed,
    ts_processed,
    COALESCE(ts_analyzed_version, ts_analyzed) AS ts_first_analyzed
  FROM
    sorting_hat_proposals_prev
  WHERE
    rn = 1
)

SELECT
  shp.id_proposal,
  rg.id_documentation_ebdb AS id_proposal_from_rg,
  cap.id_first_credit_analysis,
  cap.id_last_credit_analysis,
  cap.id_first_variant,
  cap.id_last_variant,
  dti.income,
  rg.score AS guarantee_category,
  rg.guarantee_type AS paid_guarantee_type,
  ct.guarantee_type,
  rg.guarantee_source,
  cr.liquidity,
  ceval.proposal_last_result AS last_result,
  dti.package,
  cr.risk_category,
  shp.status,
  dti.dti,
  cap.first_category,
  cap.last_category,
  cap.last_category_not_null,
  cap.max_bypass,
  cr.score AS internal_score,
  ceval.proposal_number_evaluations AS number_evaluations,
  shp.ts_analyzed,
  shp.ts_first_analyzed,
  ceval.ts_proposal_first_credit_evaluation_positive AS ts_first_credit_evaluation_positive,
  rg.ts_paid AS ts_guarantee_paid,
  ceval.ts_proposal_last_credit_evaluation_positive AS ts_last_credit_evaluation_positive,
  shp.ts_processed
FROM
  sorting_hat_proposals AS shp
LEFT JOIN
  credit_analysis_proposals AS cap
    ON shp.id_proposal = cap.id_proposal
LEFT JOIN
  credit_evaluations AS ceval
    ON shp.id_proposal = ceval.id_proposal
LEFT JOIN
  dti
    ON shp.id_proposal = dti.id_proposal
LEFT JOIN
  datalake_sorting_hat_clean.screening_result AS cr
    ON shp.id_proposal = cr.id_proposal
LEFT JOIN
  datalake_rental_guarantee.guarantee AS rg
    ON shp.id_proposal = rg.id_documentation_ebdb
LEFT JOIN
  datalake_ebdb_clean.contract AS ct
    ON shp.id_proposal = ct.id_proposal