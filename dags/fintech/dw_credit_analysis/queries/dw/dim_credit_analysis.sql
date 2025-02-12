WITH credit_engine AS (
  SELECT DISTINCT
    ar.id_analysis_request,
    ar.id_proposal,
    ch.id_checklist
  FROM
    datalake_credit_analysis.credit_engine_analysis_request AS ar
  LEFT JOIN datalake_credit_analysis.credit_engine_checklist AS ch
    ON ch.id_analysis_request = ar.id_analysis_request
  WHERE ch.is_current_checklist = TRUE
)
SELECT
  ca.id_credit_analysis,
  ca.id_proposal,
  ce.id_analysis_request,
  ce.id_checklist,
  ca.id_analyst,
  ca.bypass,
  ca.category,
  ca.category_within_ca,
  ca.category_within_proposal,
  ca.documentation_policy,
  ca.guarantee_category,
  ca.level,
  ca.paid_guarantee_type,
  ca.standalone_factor,
  ca.reason,
  ca.risk_category_canon,
  ca.internal_score,
  ca.max_bypass,
  ca.result,
  ca.guarantee_offered,
  ca.guarantee_accepted,
  ca.is_bypass,
  ca.is_manual_analysis,
  ca.is_reprocessed,
  ca.ts_guarantee_accepted,
  ca.ts_credit_analysis_created,
  NOW() AS ts_load
FROM
  datalake_credit_analysis.credit_analysis AS ca
LEFT JOIN
  credit_engine AS ce
    ON ce.id_proposal = ca.id_proposal
